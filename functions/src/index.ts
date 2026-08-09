import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

// REGION must match the project's Firestore database region — verify at deploy
// time (gcloud firestore databases describe --database='(default)').
const REGION = 'asia-southeast1';

initializeApp();
const db = getFirestore();

type NotificationType =
  | 'queue_called'
  | 'sos_new'
  | 'booking_created'
  | 'booking_cancelled'
  | 'morning_reminder'
  | 'staff_ping'
  | 'noshow_offer';

const CHANNEL_DEFAULT = 'healthcare_default';
const CHANNEL_SOS = 'sos_channel';

// Thailand is fixed UTC+7 (no DST). Appointments store Buddhist-era
// dd/MM/yyyy date strings, e.g. '03/07/2569' — this must byte-match.
function bangkokThaiDateString(now = new Date()): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Bangkok', day: '2-digit', month: '2-digit', year: 'numeric',
  }).formatToParts(now).map((p) => [p.type, p.value]));
  return `${parts.day}/${parts.month}/${Number(parts.year) + 543}`;
}

interface HistoryFields {
  uid: string;
  type: NotificationType;
  title: string;
  body: string;
  refId: string;
}

// Writes the notifications history doc FIRST; the doc doubles as the
// send-dedupe record since Firestore triggers are at-least-once.
async function createHistory(docId: string, fields: HistoryFields): Promise<boolean> {
  try {
    await db.collection('notifications').doc(docId).create({
      ...fields,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
    return true;
  } catch (error: any) {
    const code = error?.code;
    const message = typeof error?.message === 'string' ? error.message : '';
    if (code === 6 || message.includes('already exists')) {
      return false;
    }
    throw error;
  }
}

interface SendPayload {
  type: NotificationType;
  title: string;
  body: string;
  refId: string;
  channelId: string;
}

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

// Best-effort: a send failure never throws out of this helper.
async function sendToUser(uid: string, payload: SendPayload): Promise<void> {
  const { type, title, body, refId, channelId } = payload;
  try {
    const userSnap = await db.collection('users').doc(uid).get();
    const tokens: unknown = userSnap.data()?.fcmTokens;
    if (!Array.isArray(tokens)) {
      return;
    }
    const stringTokens = tokens.filter((t): t is string => typeof t === 'string');
    if (stringTokens.length === 0) {
      return;
    }

    const deadTokens: string[] = [];
    let successCount = 0;
    let failureCount = 0;

    for (const tokenChunk of chunk(stringTokens, 500)) {
      const response = await getMessaging().sendEachForMulticast({
        tokens: tokenChunk,
        notification: { title, body },
        data: { type, refId },
        android: { priority: 'high', notification: { channelId } },
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
      response.responses.forEach((res, idx) => {
        if (res.success) return;
        const errorCode = res.error?.code;
        if (
          errorCode === 'messaging/registration-token-not-registered' ||
          errorCode === 'messaging/invalid-registration-token' ||
          errorCode === 'messaging/invalid-argument'
        ) {
          deadTokens.push(tokenChunk[idx]);
        }
      });
    }

    if (deadTokens.length > 0) {
      await db.collection('users').doc(uid).update({
        fcmTokens: FieldValue.arrayRemove(...deadTokens),
      });
    }

    logger.info('sendToUser', { uid, type, successCount, failureCount, prunedCount: deadTokens.length });
  } catch (error) {
    logger.error('sendToUser failed', { uid, type, error });
  }
}

export const onQueueCalled = onDocumentUpdated(
  { document: 'appointments/{id}', region: REGION },
  async (event) => {
    try {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();
      if (!before || !after) return;
      if (before.status === after.status) return;
      if (after.status !== 'เรียกคิว') return;

      const patientUid = after.patientUid;
      if (typeof patientUid !== 'string' || patientUid.length === 0) return;

      const refId = event.params.id;
      const docId = `${event.id}_${patientUid}`;
      const queueNo = after.queueNo ?? '-';
      const title = 'ถึงคิวของคุณแล้ว';
      const body = `คิวหมายเลข ${queueNo} ถูกเรียกแล้ว กรุณาเข้ารับบริการ`;

      if (await createHistory(docId, { uid: patientUid, type: 'queue_called', title, body, refId })) {
        await sendToUser(patientUid, { type: 'queue_called', title, body, refId, channelId: CHANNEL_DEFAULT });
      }
    } catch (error) {
      logger.error('onQueueCalled failed', error);
    }
  }
);

// Auto-calls the next waiting patient for the SAME staff+date once a slot
// frees up — either the previous patient finished treatment ('เสร็จสิ้น') or
// a called/treating patient was cancelled out from under the queue. Replaces
// the staff UI's manual "เรียกคิวถัดไป" button, which was removed — this is
// now the ONLY mechanism that advances a stalled queue, so it must be robust
// against at-least-once trigger delivery (see idempotency note below).
export const autoCallNextOnComplete = onDocumentUpdated(
  { document: 'appointments/{id}', region: REGION },
  async (event) => {
    try {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();
      if (!before || !after) return;
      if (before.status === after.status) return;
      const freedSlot =
        after.status === 'เสร็จสิ้น' ||
        (['เรียกคิว', 'กำลังรักษา'].includes(before.status) && after.status === 'ยกเลิก');
      if (!freedSlot) return;

      const staffUid = after.staffUid;
      const date = after.date;
      if (typeof staffUid !== 'string' || staffUid.length === 0) return;
      if (typeof date !== 'string' || date.length === 0) return;

      // 2 equality filters — no composite index required (matches the
      // pickNextCandidate query shape used by checkLateAppointments).
      const snap = await db.collection('appointments').where('date', '==', date).where('staffUid', '==', staffUid).get();

      // If someone for this staff is already called/treating, a slot did NOT
      // actually free up for THIS staff right now — skip. (Covers the rare
      // case of two machines/queues under one staffUid; don't double-call.)
      const alreadyActive = snap.docs.some((d) => ['เรียกคิว', 'กำลังรักษา'].includes(d.data().status));
      if (alreadyActive) return;

      const waiting = snap.docs
        .filter((d) => d.data().status === 'กำลังรอ')
        .sort((a, b) => String(a.data().queueNo ?? '').localeCompare(String(b.data().queueNo ?? '')));
      const next = waiting[0];
      if (!next) return;

      // Transaction re-validates the candidate's status fresh before writing —
      // the primary idempotency guard against duplicate at-least-once trigger
      // invocations for the same underlying event (both invocations converge
      // on the same candidate and the same write, which is a harmless no-op
      // on the second attempt once the first has committed).
      await db.runTransaction(async (tx) => {
        const freshSnap = await tx.get(next.ref);
        if (!freshSnap.exists) return;
        if (freshSnap.data()!.status !== 'กำลังรอ') return; // already handled by a concurrent invocation
        tx.update(next.ref, { status: 'เรียกคิว', updatedAt: FieldValue.serverTimestamp() });
      });
      // onQueueCalled (separate trigger, fires on this same write) sends the
      // "ถึงคิวของคุณแล้ว" push — no need to duplicate that here.

      logger.info('autoCallNextOnComplete', { freedApptId: event.params.id, calledApptId: next.id, staffUid, date });
    } catch (error) {
      logger.error('autoCallNextOnComplete failed', error);
    }
  }
);

export const onBookingCreated = onDocumentCreated(
  { document: 'appointments/{id}', region: REGION },
  async (event) => {
    try {
      const data = event.data?.data();
      if (!data) return;
      if (data.status !== 'กำลังรอ') return;

      const staffUid = data.staffUid;
      if (typeof staffUid !== 'string' || staffUid.length === 0) return;

      const refId = event.params.id;
      const docId = `${event.id}_${staffUid}`;
      const queueNo = data.queueNo ?? '-';
      const date = data.date ?? '-';
      const time = data.time ?? '-';
      const title = 'มีการจองคิวใหม่';
      // PRIVACY: do NOT include patientName in title/body.
      const body = `คิว ${queueNo} วันที่ ${date} เวลา ${time} ถูกเพิ่มในตารางของคุณ`;

      if (await createHistory(docId, { uid: staffUid, type: 'booking_created', title, body, refId })) {
        await sendToUser(staffUid, { type: 'booking_created', title, body, refId, channelId: CHANNEL_DEFAULT });
      }
    } catch (error) {
      logger.error('onBookingCreated failed', error);
    }
  }
);

export const onBookingCancelled = onDocumentUpdated(
  { document: 'appointments/{id}', region: REGION },
  async (event) => {
    try {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();
      if (!before || !after) return;
      if (before.status === after.status) return;
      if (after.status !== 'ยกเลิก') return;

      const queueNo = after.queueNo ?? '-';
      const date = after.date ?? '-';
      const time = after.time ?? '-';
      const staffUid = typeof after.staffUid === 'string' ? after.staffUid : '';
      const patientUid = typeof after.patientUid === 'string' ? after.patientUid : '';
      const cancelledBy = after.cancelledBy;

      let recipients: string[];
      let title: string;
      let body: string;

      if (cancelledBy === 'patient') {
        recipients = [staffUid];
        title = 'คิวถูกยกเลิก';
        body = `คิว ${queueNo} วันที่ ${date} เวลา ${time} ถูกยกเลิกโดยผู้ป่วย`;
      } else if (cancelledBy === 'staff') {
        recipients = [patientUid];
        title = 'คิวของคุณถูกยกเลิก';
        body = `คิว ${queueNo} วันที่ ${date} ถูกยกเลิก กรุณาเปิดแอปเพื่อดูรายละเอียดหรือจองคิวใหม่`;
      } else if (cancelledBy === 'system_noshow') {
        recipients = [patientUid, staffUid];
        title = 'คิวถูกยกเลิก (ไม่มาตามนัด)';
        body = `คิว ${queueNo} วันที่ ${date} เวลา ${time} ถูกยกเลิกเนื่องจากไม่มารับบริการภายในเวลาที่กำหนด`;
      } else if (cancelledBy === 'system_late') {
        recipients = [patientUid, staffUid];
        title = 'คิวถูกยกเลิก (มาสายเกินกำหนด)';
        body = `คิว ${queueNo} วันที่ ${date} เวลา ${time} ถูกยกเลิกเนื่องจากมาสายเกินเวลานัดกว่า 5 นาที`;
      } else {
        recipients = [staffUid, patientUid];
        title = 'คิวถูกยกเลิก';
        body = `คิว ${queueNo} วันที่ ${date} ถูกยกเลิกแล้ว`;
      }

      const uniqueRecipients = Array.from(new Set(recipients.filter((uid) => uid.length > 0)));
      const refId = event.params.id;

      for (const uid of uniqueRecipients) {
        const docId = `${event.id}_${uid}`;
        if (await createHistory(docId, { uid, type: 'booking_cancelled', title, body, refId })) {
          await sendToUser(uid, { type: 'booking_cancelled', title, body, refId, channelId: CHANNEL_DEFAULT });
        }
      }
    } catch (error) {
      logger.error('onBookingCancelled failed', error);
    }
  }
);

export const onSosCreated = onDocumentCreated(
  { document: 'sos_alerts/{id}', region: REGION },
  async (event) => {
    try {
      const data = event.data?.data();
      if (!data) return;
      if (data.status !== 'รอรับเรื่อง') return;

      const refId = event.params.id;
      const title = 'แจ้งเตือนฉุกเฉิน SOS';
      // PRIVACY: never include the SOS issue text or patient name.
      const body = 'มีเหตุฉุกเฉินใหม่ กรุณาเปิดแอปเพื่อรับเรื่อง';

      // Staff ONLY — not admins (admin UI is user management only).
      const staffSnap = await db.collection('users').where('role', '==', 'staff').get();

      for (const staffDoc of staffSnap.docs) {
        const staffUid = staffDoc.id;
        const docId = `${event.id}_${staffUid}`;
        if (await createHistory(docId, { uid: staffUid, type: 'sos_new', title, body, refId })) {
          await sendToUser(staffUid, { type: 'sos_new', title, body, refId, channelId: CHANNEL_SOS });
        }
      }
    } catch (error) {
      logger.error('onSosCreated failed', error);
    }
  }
);

export const morningReminders = onSchedule(
  { schedule: '0 7 * * *', timeZone: 'Asia/Bangkok', region: REGION },
  async () => {
    try {
      const today = bangkokThaiDateString();
      const todayKey = today.replace(/\//g, '-');

      const snap = await db.collection('appointments').where('date', '==', today).get();

      for (const doc of snap.docs) {
        const data = doc.data();
        if (data.status !== 'กำลังรอ') continue;

        const patientUid = data.patientUid;
        if (typeof patientUid !== 'string' || patientUid.length === 0) continue;

        const refId = doc.id;
        const docId = `${patientUid}_${todayKey}_reminder`;
        const queueNo = data.queueNo ?? '-';
        const time = data.time ?? '-';
        const title = 'แจ้งเตือนนัดหมายวันนี้';
        const body = `คุณมีคิวหมายเลข ${queueNo} เวลา ${time} วันนี้ กรุณามาถึงก่อนเวลานัด`;

        if (await createHistory(docId, { uid: patientUid, type: 'morning_reminder', title, body, refId })) {
          await sendToUser(patientUid, { type: 'morning_reminder', title, body, refId, channelId: CHANNEL_DEFAULT });
        }
      }
    } catch (error) {
      logger.error('morningReminders failed', error);
    }
  }
);

// ==========================================
// Auto-cancel stale appointments + "come in earlier?" offer to the next queue
// ==========================================
//
// Two independent staleness triggers both funnel into the SAME
// cancelAppointmentAndOfferNext(): (1) still 'กำลังรอ' and past its own
// scheduled time by LATE_GRACE_MS, (2) 'เรียกคิว' but never checked in within
// NOSHOW_GRACE_MS. Both auto-cancel UNCONDITIONALLY (whether or not a next
// candidate exists to notify) and never touch queueNo/time — no reordering,
// ever. The "come in earlier?" nudge is purely informational: two concrete
// arrival-time options (now+5min, now+10min), or decline; no response within
// OFFER_WINDOW_MS is treated as a decline.

const LATE_GRACE_MS = 5 * 60 * 1000; // 5 minutes past scheduled time -> auto-cancel
const NOSHOW_GRACE_MS = 10 * 60 * 1000; // 10 minutes called but not checked in -> auto-cancel
const OFFER_WINDOW_MS = 5 * 60 * 1000; // "come in earlier?" offer window; no response = declined

// Formats a UTC millis instant as Bangkok wall-clock "HH:MM" — used for the
// offer's arrival-time options (option labels only, not stored as
// appointment.time, so this doesn't need the Buddhist-date round-trip that
// apptDateTimeUtcMillis does).
function formatBangkokTime(utcMillis: number): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Bangkok', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(utcMillis).map((p) => [p.type, p.value]));
  return `${parts.hour}:${parts.minute}`;
}

// Converts a stored Buddhist-era 'dd/MM/yyyy' date + 'HH:MM' time into a real
// UTC millis instant. Thailand is fixed UTC+7 (no DST) — subtract the offset
// directly rather than relying on the Cloud Functions runtime's local
// timezone (NOT guaranteed to be Bangkok even though the schedule's
// `timeZone` option is set — that only controls when the schedule fires).
function apptDateTimeUtcMillis(thaiDate: unknown, time: unknown): number | null {
  if (typeof thaiDate !== 'string' || typeof time !== 'string') return null;
  const dateMatch = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(thaiDate);
  const timeMatch = /^(\d{2}):(\d{2})$/.exec(time);
  if (!dateMatch || !timeMatch) return null;
  const [, dd, mm, yyyyBE] = dateMatch;
  const [, hh, min] = timeMatch;
  const gregorianYear = Number(yyyyBE) - 543;
  if (gregorianYear < 2000 || gregorianYear > 2100) return null; // sanity guard
  return Date.UTC(gregorianYear, Number(mm) - 1, Number(dd), Number(hh) - 7, Number(min));
}

// Finds the earliest-queueNo, still-waiting, same-staff appointment (other
// than [excludeApptId]) with no offer currently in flight — the candidate to
// notify. queueNo is a GLOBAL daily counter across all staff, so this must
// filter by staffUid, never assume numeric adjacency. A patient who
// previously declined/accepted an earlier offer is still eligible again later
// (only an actively 'pending' offer blocks re-selection).
function pickNextCandidate(
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
  excludeApptId: string
): FirebaseFirestore.QueryDocumentSnapshot | null {
  const candidates = docs.filter((d) => {
    const data = d.data();
    return d.id !== excludeApptId && data.status === 'กำลังรอ' && data.noShowOfferStatus !== 'pending';
  });
  candidates.sort((a, b) => String(a.data().queueNo ?? '').localeCompare(String(b.data().queueNo ?? '')));
  return candidates[0] ?? null;
}

export const checkLateAppointments = onSchedule(
  { schedule: 'every 2 minutes', timeZone: 'Asia/Bangkok', region: REGION },
  async () => {
    try {
      const now = Date.now();
      const today = bangkokThaiDateString();
      const snap = await db.collection('appointments').where('date', '==', today).get();
      const allDocs = snap.docs;

      let scanned = 0;
      let lateCancelled = 0;
      let noShowCancelled = 0;
      let offersDeclinedByTimeout = 0;

      for (const doc of allDocs) {
        const data = doc.data();
        scanned++;

        // ---- Auto-decline stale pending "come in earlier?" offers ----
        if (data.noShowOfferStatus === 'pending') {
          const expiresAtMs = (data.noShowOfferExpiresAt as Timestamp | undefined)?.toMillis();
          if (expiresAtMs !== undefined && now >= expiresAtMs) {
            await doc.ref.update({ noShowOfferStatus: 'declined' }).catch((error) =>
              logger.error('auto-decline noShowOffer failed', { apptId: doc.id, error }));
            offersDeclinedByTimeout++;
          }
        }

        // ---- No-show: called but not checked in within 10 min ----
        if (data.status === 'เรียกคิว') {
          const calledAtMs = (data.updatedAt as Timestamp | undefined)?.toMillis();
          if (calledAtMs !== undefined && now - calledAtMs >= NOSHOW_GRACE_MS) {
            const didCancel = await cancelAppointmentAndOfferNext(doc, data, allDocs, now, 'system_noshow');
            if (didCancel) noShowCancelled++;
          }
          continue;
        }

        // ---- Late: still waiting, past own scheduled time by 5+ min ----
        if (data.status === 'กำลังรอ') {
          const apptMillis = apptDateTimeUtcMillis(data.date, data.time);
          if (apptMillis === null) {
            logger.warn('checkLateAppointments: unparseable date/time', { id: doc.id, date: data.date, time: data.time });
            continue;
          }
          if (now >= apptMillis + LATE_GRACE_MS) {
            const didCancel = await cancelAppointmentAndOfferNext(doc, data, allDocs, now, 'system_late');
            if (didCancel) lateCancelled++;
          }
          continue;
        }
      }

      logger.info('checkLateAppointments', { scanned, lateCancelled, noShowCancelled, offersDeclinedByTimeout });
    } catch (error) {
      logger.error('checkLateAppointments failed', error);
    }
  }
);

// Auto-cancels a stale appointment — either late for its own scheduled time
// ('system_late') or called but never checked in ('system_noshow') — then
// sends the next same-staff waiting patient a courtesy "can you come in
// earlier?" nudge with two concrete arrival-time options. UNCONDITIONAL: the
// cancel happens regardless of whether a next candidate exists to notify.
// Deliberately does NOT touch queueNo/time on either doc — no reordering,
// purely informational; the ordinary autoCallNextOnComplete trigger (fired by
// this same ยกเลิก write, when applicable) is what actually advances the
// queue mechanically. Returns true if the cancel actually happened (false if
// a concurrent change — e.g. staff already acted on it — beat us to it).
async function cancelAppointmentAndOfferNext(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
  data: FirebaseFirestore.DocumentData,
  allDocs: FirebaseFirestore.QueryDocumentSnapshot[],
  now: number,
  cancelledBy: 'system_late' | 'system_noshow'
): Promise<boolean> {
  const expectedStatus = cancelledBy === 'system_noshow' ? 'เรียกคิว' : 'กำลังรอ';
  let cancelled = false;
  try {
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || fresh.data()!.status !== expectedStatus) return; // already handled/changed concurrently
      tx.update(doc.ref, { status: 'ยกเลิก', cancelledAt: FieldValue.serverTimestamp(), cancelledBy });
      cancelled = true;
    });
  } catch (error) {
    logger.error('cancelAppointmentAndOfferNext: cancel transaction failed', { apptId: doc.id, cancelledBy, error });
    return false;
  }
  if (!cancelled) return false;

  // Release the queue_slots lock — mirrors QueueSlotService.release(), which
  // this server-side cancel bypasses since it doesn't go through the client.
  const staffUid = data.staffUid;
  const time = data.time;
  const dateStr = data.date;
  if (typeof staffUid === 'string' && staffUid.length > 0 && typeof time === 'string' && typeof dateStr === 'string') {
    try {
      const dateKey = dateStr.replace(/\//g, '-');
      await db.collection('queue_slots').doc(`${staffUid}_${dateKey}`).update({ [`bookedTimes.${time}`]: false });
    } catch (error) {
      logger.error('cancelAppointmentAndOfferNext: release slot failed', { apptId: doc.id, error });
    }
  }

  // onBookingCancelled (separate trigger, fires on this same write) already
  // notifies the cancelled patient + staff — no need to duplicate that here.

  // Courtesy nudge to the next same-staff waiting patient.
  if (typeof staffUid !== 'string' || staffUid.length === 0) return true;
  const next = pickNextCandidate(allDocs, doc.id);
  if (!next) return true;
  const nextData = next.data();
  const nextPatientUid = nextData.patientUid;
  if (typeof nextPatientUid !== 'string' || nextPatientUid.length === 0) return true;

  const option1 = formatBangkokTime(now + 5 * 60 * 1000);
  const option2 = formatBangkokTime(now + 10 * 60 * 1000);
  const expiresAt = Timestamp.fromMillis(now + OFFER_WINDOW_MS);

  try {
    await next.ref.update({
      noShowOfferStatus: 'pending',
      noShowOfferFromApptId: doc.id,
      noShowOfferOptions: [option1, option2],
      noShowOfferSentAt: FieldValue.serverTimestamp(),
      noShowOfferExpiresAt: expiresAt,
      noShowOfferChosenTime: FieldValue.delete(),
    });
  } catch (error) {
    logger.error('cancelAppointmentAndOfferNext: write noShowOffer failed', { apptId: doc.id, nextApptId: next.id, error });
    return true;
  }

  const title = 'สนใจเข้ารับบริการไวขึ้นไหม?';
  const body = `คิวก่อนหน้าไม่มาตามนัด สะดวกมาเวลา ${option1} หรือ ${option2} ไหม?`;
  const refId = doc.id;
  if (await createHistory(`${doc.id}_${nextPatientUid}_noshow_offer`, { uid: nextPatientUid, type: 'noshow_offer', title, body, refId })) {
    await sendToUser(nextPatientUid, { type: 'noshow_offer', title, body, refId, channelId: CHANNEL_DEFAULT });
  }
  return true;
}

interface RespondToNoShowOfferRequest {
  apptId: string; // the OFFERED patient's own appointment doc id
  chosenTime: string | null; // one of noShowOfferOptions, or null to decline
}

// Callable — the offered patient accepting/declining the "come in earlier?"
// courtesy nudge. NEVER touches queueNo/time — chosenTime is purely
// informational (surfaced to staff), so a plain validated update is enough;
// no swap transaction needed.
export const respondToNoShowOffer = onCall<RespondToNoShowOfferRequest>({ region: REGION, enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  const { apptId, chosenTime } = request.data;
  if (typeof apptId !== 'string' || apptId.length === 0) {
    throw new HttpsError('invalid-argument', 'apptId ไม่ถูกต้อง');
  }
  if (chosenTime !== null && typeof chosenTime !== 'string') {
    throw new HttpsError('invalid-argument', 'chosenTime ไม่ถูกต้อง');
  }

  const ref = db.collection('appointments').doc(apptId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'ไม่พบคิวนี้');
    const d = snap.data()!;
    if (d.patientUid !== uid) throw new HttpsError('permission-denied', 'ไม่ใช่คิวของคุณ');
    if (d.noShowOfferStatus !== 'pending') {
      throw new HttpsError('failed-precondition', 'ข้อเสนอนี้ไม่สามารถใช้ได้แล้ว');
    }
    const expiresAtMs = (d.noShowOfferExpiresAt as Timestamp | undefined)?.toMillis();
    if (expiresAtMs !== undefined && Date.now() >= expiresAtMs) {
      tx.update(ref, { noShowOfferStatus: 'declined' });
      throw new HttpsError('failed-precondition', 'ข้อเสนอหมดเวลาแล้ว');
    }
    if (chosenTime === null) {
      tx.update(ref, { noShowOfferStatus: 'declined' });
      return;
    }
    const options: unknown = d.noShowOfferOptions;
    if (!Array.isArray(options) || !options.includes(chosenTime)) {
      throw new HttpsError('invalid-argument', 'เวลาที่เลือกไม่ตรงกับตัวเลือกที่เสนอ');
    }
    tx.update(ref, { noShowOfferStatus: 'accepted', noShowOfferChosenTime: chosenTime });
  });

  return { ok: true };
});

interface RedeemStaffInviteRequest {
  code: string;
  fullname: string;
  email: string;
  specialization: string;
}

// Callable — validates + "burns" the staff invite code and creates users/{uid}
// in one Admin SDK transaction (bypasses firestore.rules by design). This is
// now the ONLY path that can read/consume settings/staff_invite.invite_code —
// the Firestore doc itself is admin-read-only (see firestore.rules), so the
// code is never exposed to an unauthenticated client via direct REST reads.
// Client must create the Firebase Auth account FIRST (request.auth.uid),
// then call this; on failure the client rolls back the orphaned Auth account.
export const redeemStaffInvite = onCall<RedeemStaffInviteRequest>({ region: REGION, enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  const { code, fullname, email, specialization } = request.data;
  if (typeof code !== 'string' || code.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Invite code ไม่ถูกต้อง');
  }
  if (typeof fullname !== 'string' || fullname.trim().length === 0 ||
      typeof email !== 'string' || email.trim().length === 0 ||
      typeof specialization !== 'string' || specialization.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'ข้อมูลไม่ครบถ้วน');
  }

  const inviteRef = db.collection('settings').doc('staff_invite');
  const userRef = db.collection('users').doc(uid);
  await db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(inviteRef);
    const data = inviteSnap.data();
    const currentCode = data?.invite_code as string | undefined;
    const used = (data?.used as boolean | undefined) ?? false;
    if (!currentCode || currentCode !== code.trim() || used) {
      throw new HttpsError('failed-precondition', 'Invite Code ไม่ถูกต้องหรือถูกใช้ไปแล้ว');
    }
    tx.set(userRef, {
      uid, fullname: fullname.trim(), email: email.trim(), role: 'staff',
      specialization: specialization.trim(), createdAt: FieldValue.serverTimestamp(),
      // NOT gated on email verification — the invite code (admin-issued,
      // single-use) is already a stronger gate than public patient signup,
      // and staff Firestore doc creation can't be deferred past this point
      // anyway without leaving the burned code's account in limbo.
    });
    tx.update(inviteRef, { used: true, usedBy: uid, usedAt: FieldValue.serverTimestamp() });
  });

  return { ok: true };
});

interface PingPatientRequest {
  apptId: string;
}

// Callable — lets staff manually re-notify the patient tied to a specific
// queue card, independent of (and in addition to) the automatic status-change
// triggers (onQueueCalled etc.). Any signed-in staff/admin may ping any
// appointment — matches the existing firestore.rules invariant that staff
// writes to `appointments` aren't restricted to their own staffUid.
export const pingPatient = onCall<PingPatientRequest>({ region: REGION, enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  const { apptId } = request.data;
  if (typeof apptId !== 'string' || apptId.length === 0) {
    throw new HttpsError('invalid-argument', 'apptId ไม่ถูกต้อง');
  }

  const callerSnap = await db.collection('users').doc(uid).get();
  const callerRole = callerSnap.data()?.role;
  if (callerRole !== 'staff' && callerRole !== 'admin') {
    throw new HttpsError('permission-denied', 'เฉพาะเจ้าหน้าที่เท่านั้นที่แจ้งเตือนได้');
  }

  const apptSnap = await db.collection('appointments').doc(apptId).get();
  if (!apptSnap.exists) throw new HttpsError('not-found', 'ไม่พบคิวนี้');
  const appt = apptSnap.data()!;
  const patientUid = appt.patientUid;
  if (typeof patientUid !== 'string' || patientUid.length === 0) {
    throw new HttpsError('failed-precondition', 'ไม่พบผู้ป่วยของคิวนี้');
  }

  const queueNo = appt.queueNo ?? '-';
  const title = 'แจ้งเตือนจากเจ้าหน้าที่';
  const body = `กรุณาตรวจสอบคิวหมายเลข ${queueNo} ของคุณ เจ้าหน้าที่กำลังรอเรียกคุณเข้ารับบริการ`;
  const refId = apptId;
  // No dedupe by design — staff may intentionally ping more than once (e.g.
  // patient stepped away); each tap gets its own history record.
  const docId = `${apptId}_ping_${Date.now()}`;
  if (await createHistory(docId, { uid: patientUid, type: 'staff_ping', title, body, refId })) {
    await sendToUser(patientUid, { type: 'staff_ping', title, body, refId, channelId: CHANNEL_DEFAULT });
  }

  return { sent: true };
});
