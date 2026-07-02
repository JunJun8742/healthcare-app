# Push Notifications — Design

Date: 2026-07-03
Status: approved (architecture user-approved; detail design synthesized from two independent consultant passes — deep-reasoner and Codex — arbitrated by the orchestrator, security claims re-verified against code).

## Goal

Real push notifications for the healthcare queue app: delivered on Android even when the app is closed, for four event families, plus an in-app notification history behind the existing placeholder แจ้งเตือน screen.

## Scope decisions (user-approved)

- Events: patient queue-called, patient morning appointment reminder, staff new-SOS, staff new/cancelled booking (cancelled also notifies the patient when staff cancels).
- Android only. No iOS/APNs, no web push.
- Closed-app delivery required → FCM + Firestore-triggered Cloud Functions; Firebase project upgrades to Blaze (free tier covers clinic-scale usage).
- In-app history screen with unread badge, backed by a new `notifications` collection.

## Architecture

```
staff/patient action → Firestore write → Cloud Function trigger
                                            ├─ create notifications/{deterministicId}  (history + dedupe)
                                            └─ FCM multicast to users/{uid}.fcmTokens  (system tray push)
Flutter app: receives + displays; never sends.
```

### Components

1. **`functions/` codebase** — TypeScript, Node 22, firebase-functions v2 (^6), firebase-admin (^13). Region constant `asia-southeast1` — verify the project's Firestore region at deploy time (Firestore triggers must co-locate with the database region). Five functions:

| Function | Trigger | Guard | Recipients |
|---|---|---|---|
| `onQueueCalled` | `appointments/{id}` updated | `before.status != after.status && after.status == 'เรียกคิว' && patientUid` | patient |
| `onBookingCreated` | `appointments/{id}` created | `status == 'กำลังรอ' && staffUid` | assigned staff |
| `onBookingCancelled` | `appointments/{id}` updated | `before.status != after.status && after.status == 'ยกเลิก'` | see routing below |
| `onSosCreated` | `sos_alerts/{id}` created | `status == 'รอรับเรื่อง'` | all users with role `staff` (NOT admins — admin UI is user management only; avoids leaking clinical events) |
| `morningReminders` | schedule `0 7 * * *`, timeZone `Asia/Bangkok` | appointments where `date == today` (single equality query), filtered in code to `status == 'กำลังรอ'` | each patient with a waiting appointment today |

2. **`notifications` collection** — written only by functions (Admin SDK bypasses rules):
   `{ uid, type, title, body, refId, read: false, createdAt: serverTimestamp, expiresAt: now+30d }`
   `type ∈ queue_called | sos_new | booking_created | booking_cancelled | morning_reminder`; `refId` = source doc id.
   Retention: Firestore **TTL policy on `expiresAt`** (one-time setup at deploy: console or `gcloud firestore fields ttls update expiresAt --collection-group=notifications --enable-ttl`). No cleanup code. If TTL is never enabled, the collection just grows slowly — harmless at clinic scale.

3. **Flutter app (receiver)** — `firebase_messaging` + `flutter_local_notifications`. Token registration, foreground display bridge, tap routing, history screen. Details below.

## Key design decisions

### Token lifecycle
- `users/{uid}.fcmTokens` is a **plain array of token strings** (`arrayUnion`/`arrayRemove`). No metadata map — nothing reads it, and the map costs two extra packages. (Existing rules already permit self-writes of non-`role` fields — verified `firestore.rules:35-36`.)
- Register in `AuthGate` after the role doc resolves (covers auto-login): `requestPermission()` → `getToken()` (try/catch — emulators without Play services throw) → `arrayUnion`. Guarded to run once per session; must never block or crash the build.
- `onTokenRefresh`: single global subscription → `arrayUnion` the new token; stale ones die via pruning.
- **Logout** (every `signOut()` site): best-effort `arrayRemove(currentToken)` + `FirebaseMessaging.instance.deleteToken()`, in try/catch, never blocking logout. Mandatory for shared clinic phones — a logged-out staffer must not keep receiving SOS pushes.
- **Pruning**: after each multicast, tokens failing with `messaging/registration-token-not-registered` or `messaging/invalid-registration-token` (and `invalid-argument` where the token is the failed element) are `arrayRemove`d from the owner's doc.

### Idempotence / dedupe
Firestore triggers are at-least-once. Every send is paired with a **deterministic history doc ID**; the function `create()`s the history doc FIRST and skips the FCM send on `ALREADY_EXISTS`. So the history doc doubles as the send-dedupe record.
- Event triggers: docId = `${event.id}_${recipientUid}` (event.id is stable across retries; does not suppress genuine future re-calls).
- Reminders: docId = `${patientUid}_${todayKey}_reminder` where todayKey = date with `/` → `-` (slashes are illegal in doc IDs) — semantic ID also protects against accidental double runs.
- Functions never rethrow (no automatic retries configured); failures are logged. Push is best-effort by design — in-app Firestore streams remain the source of truth, especially for SOS.

### Cancel actor attribution
- App writes `cancelledBy: 'patient' | 'staff'` at cancel time: patient sites `lib/main.dart:1304`, `:2157` add it to the existing update; staff cancel passes `{'cancelledBy': 'staff'}` through `_changeStatus`'s `extra` mechanism (rides the existing undo/restore machinery).
- Function routing: `'patient'` → notify staff; `'staff'` → notify patient; **absent** (old APKs still circulating via Line, or console edits) → notify BOTH with neutral copy, so no cancellation is ever silent.
- Rules: patient cancel rule tightened to `resource.status == 'กำลังรอ'` (matches the UI, which only offers cancel while waiting) + `affectedKeys().hasOnly(['status','cancelledAt','cancelledBy'])`. hasOnly permits a subset → old APKs sending only `{status, cancelledAt}` keep working.

### Buddhist date replication (reminders)
`appointments.date` is `dd/MM/${gregorianYear + 543}` (verified `lib/main.dart:1475`, stored verbatim at `:1562`). Node side must byte-match:

```ts
function bangkokThaiDateString(now = new Date()): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Bangkok', day: '2-digit', month: '2-digit', year: 'numeric',
  }).formatToParts(now).map(p => [p.type, p.value]));
  return `${parts.day}/${parts.month}/${Number(parts.year) + 543}`;
}
```

(Thailand is fixed UTC+7, no DST; Intl keeps intent explicit.)

### Message shape
**notification + data** messages (not data-only): the system tray renders them with the app terminated, and delivery survives Thai OEM battery killers (Xiaomi/OPPO/vivo) far better. Payload:

```
notification: { title, body }
data: { type, refId }
android: { priority: 'high', notification: { channelId } }
```

Channels (created at app startup, before first message): `healthcare_default` (importance high) and `sos_channel` (importance max) — staff can give SOS its own sound/behavior in system settings.

### App receive path
- Android 13+ `POST_NOTIFICATIONS` permission: declared in the manifest, requested via `FirebaseMessaging.requestPermission()` right after login resolves (not on the login screen).
- Foreground: FCM shows nothing in foreground on Android → `onMessage` bridges to a `flutter_local_notifications` heads-up on the mapped channel, payload `{type}`.
- Tap routing by `data.type` + current role:
  - patient `queue_called` / `morning_reminder` / `booking_cancelled` → `MainNavigation(initialIndex: 1)` (คิวของฉัน)
  - staff `sos_new` → `StaffNavigation(initialIndex: 1)`; staff `booking_created`/`booking_cancelled` → index 0
  - Terminated tap: `getInitialMessage` → pending-type global consumed when AuthGate builds the nav root. Background tap: `onMessageOpenedApp` → `pushAndRemoveUntil` a fresh nav root via a global navigator key. Local-notification tap: same router.
- `StaffNavigation` gains an `initialIndex` param (mirrors `MainNavigation`).
- Core library desugaring enabled in `android/app/build.gradle.kts` (required by flutter_local_notifications).

### History screen + badge
- `NotificationScreen` → StreamBuilder on `notifications` where `uid == me`, **client-side sort** by createdAt desc (no orderBy → no composite index; TTL caps the set at ~30 days). Card per item: type icon, title (bold when unread), body, relative time; tap marks `read: true`.
- Patient entry: existing home แจ้งเตือน card, now with a red unread dot (StreamBuilder on `read == false`). Staff entry: bell icon with dot in the StaffQueueScreen AppBar → same screen.
- Rules: owner-only read; update restricted to flipping `read` false→true; client create/delete denied.

### Notification copy (frozen — Thai, privacy-safe)
**No patient names, no medical/SOS issue text in push title/body** (lock-screen exposure in a healthcare context). Details live in-app behind auth.

| type | title | body |
|---|---|---|
| queue_called | ถึงคิวของคุณแล้ว | คิวหมายเลข {queueNo} ถูกเรียกแล้ว กรุณาเข้ารับบริการ |
| booking_created | มีการจองคิวใหม่ | คิว {queueNo} วันที่ {date} เวลา {time} ถูกเพิ่มในตารางของคุณ |
| booking_cancelled → staff | คิวถูกยกเลิก | คิว {queueNo} วันที่ {date} เวลา {time} ถูกยกเลิกโดยผู้ป่วย |
| booking_cancelled → patient | คิวของคุณถูกยกเลิก | คิว {queueNo} วันที่ {date} ถูกยกเลิก กรุณาเปิดแอปเพื่อดูรายละเอียดหรือจองคิวใหม่ |
| booking_cancelled → fallback (both) | คิวถูกยกเลิก | คิว {queueNo} วันที่ {date} ถูกยกเลิกแล้ว |
| sos_new | แจ้งเตือนฉุกเฉิน SOS | มีเหตุฉุกเฉินใหม่ กรุณาเปิดแอปเพื่อรับเรื่อง |
| morning_reminder | แจ้งเตือนนัดหมายวันนี้ | คุณมีคิวหมายเลข {queueNo} เวลา {time} วันนี้ กรุณามาถึงก่อนเวลานัด |

## Explicitly deferred

- Tightening the broad `users` self-update rule (needs a profile-edit field audit first; fcmTokens already fits the current rule).
- Custom SOS sound asset; admin SOS escalation setting; per-user token cap.
- iOS/web push; Cloud Functions unit-test suite (no test infra exists in this repo).

## Deploy-time checklist (manual gates)

1. Upgrade project `heal-a49e3` to Blaze (user, console, credit card).
2. `firebase login` (user, interactive) — CLI v15.19 already installed.
3. Verify Firestore region (`gcloud firestore databases describe` or console) → set `REGION` constant to match if not `asia-southeast1`.
4. `firebase deploy --only functions,firestore:rules` (also delivers the pending Phase-1 rules).
5. Enable TTL on `notifications.expiresAt`.
6. Real-device test (emulator FCM is unreliable): booking → staff call → push on locked phone; SOS → staff push; cancel both directions; foreground heads-up; tap routing. Advise staff phones to exempt the app from battery optimization.

## Verification during implementation

- Dart: `dart analyze lib/main.dart` — exactly the 5 pre-existing info lints, nothing new (`flutter analyze` is broken on this machine's non-ASCII path).
- Functions: `npm install && npm run build` (tsc) exits 0.
- Rules: reviewed by orchestrator (done — committed alongside this spec); exercised end-to-end after deploy.
