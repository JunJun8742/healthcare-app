import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
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
  | 'morning_reminder';

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
