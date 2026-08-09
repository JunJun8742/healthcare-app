# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Orchestration workflow
You (Fable) are the orchestrator. Plan, decompose, synthesize.
Reasoning-heavy phases → deep-reasoner
Mechanical work → fast-worker
Codex (/codex:rescue --background) is a cracked engineer on par with deep-reasoner, from a different perspective. Treat as a peer, not a reviewer.
High-stakes decisions: task Opus + Codex on the same problem in parallel, synthesize the best of both, without showing either the other's answer. Keep your own context lean.


## Commands

Run these from `healthcare-app/` (this directory):

```bash
# Install dependencies
flutter pub get

# Run the app (choose target device)
flutter run

# Analyze code — run after every edit
flutter analyze

# Run tests
flutter test

# Build release APK (shared manually, e.g. via Line/Drive)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Regenerate Firebase options (requires flutterfire CLI) — only when explicitly asked
flutterfire configure
```

`test/` covers `core/` (pure logic: `format.dart`, `status.dart`) and `services/` (Firestore-backed classes, exercised against `fake_cloud_firestore` via the `{FirebaseFirestore? db}` injection point — see Architecture below) using `flutter_test` + `fake_cloud_firestore` (dev dependencies). Run `flutter test` after touching any tested file; `flutter analyze` remains the first check after any Dart change, but it only catches syntax/type issues, not logic regressions — the test suite is what catches those. Widget/UI tests and Cloud Functions tests (`functions/src/index.ts`) are not covered yet.

### Cloud Functions (`functions/`)

```bash
# From functions/ — install deps once
npm install

# Typecheck — run after every edit to functions/src/index.ts (equivalent of flutter analyze for TS)
npm run build

# Deploy (requires firebase-tools + project access)
firebase deploy --only functions
```

`functions/src/index.ts` is a single file, TypeScript, Admin SDK, region `asia-southeast1` (must match the Firestore database region — verify with `gcloud firestore databases describe --database='(default)'` before changing). It is the **only** place notifications are sent — the Flutter app never sends push directly, it only reads/writes Firestore and lets triggers react.

Two function kinds: Firestore triggers (`onDocumentCreated`/`onDocumentUpdated`, fire on `appointments`/`sos_alerts` writes) and scheduled functions (`onSchedule`, cron-style). `onCall` (callable) functions are for operations the client must never be trusted to perform directly via `firestore.rules` — currently `respondToNoShowOffer` (accept/decline the "come in earlier?" nudge), `pingPatient` (staff manual re-notify), and `redeemStaffInvite` (validates + burns the staff invite code and creates `users/{uid}` server-side, so the code itself is never readable by a client — see `settings/staff_invite` below).

Shared helpers: `createHistory(docId, fields)` writes `notifications/{docId}` and doubles as the send-dedupe record (Firestore triggers are at-least-once — `docId` must be deterministic per logical event, e.g. `${apptId}_late`); `sendToUser(uid, payload)` batches FCM sends (500/request) and prunes dead tokens — both are best-effort and never throw.

## Architecture

Feature-split app with an extracted service/logic layer (Dart package: `healthcare_app`; absolute `package:healthcare_app/...` imports everywhere):

```text
lib/
  main.dart                  # bootstrap only: Firebase init + initFcmBootstrap + runApp
  app/app.dart               # HealthcareStation (MaterialApp), AuthGate role routing,
                             #   appNavigatorKey, routeFromNotification (widget mapping)
  core/
    theme.dart               # colors, spacing tokens, tTitle/tBody/tCaption
    status.dart              # QueueStatus/SosStatus constants (exact Firestore values) + statusInfo()
    format.dart              # thaiBuddhistDate, queueSlotDateKey, relativeTimeTh,
                             #   isMachineStale, compareCreatedAtDesc
    photo.dart               # encodePhotoBase64 / tryDecodePhotoBase64
    widgets.dart             # StateMessage, MachineStatusCard, icon3D
  services/                  # all Firestore/FCM I/O; classes take {FirebaseFirestore? db}
                             #   defaulting to .instance (inject fake_cloud_firestore in tests);
                             #   each file ends with a shared instance (queueSlots, availability,
                             #   appointments, sos, users, notifications)
    fcm_service.dart         # token lifecycle, notificationDestination() decision table
    queue_slot_service.dart  # queue_slots release/relock (doc ID sanitizes '/'->'-')
    availability_service.dart# staff_availability (doc ID keeps raw Thai date)
    appointment_service.dart # booking transaction -> sealed BookingOutcome, streams, status updates
    noshow_offer_service.dart# respondToNoShowOffer callable wrapper (accept/decline the nudge)
    staff_invite_service.dart# redeemStaffInvite callable wrapper (staff signup)
    sos_service.dart / user_service.dart / notification_service.dart
  features/
    auth/                    # login, register, staff_register
    patient/                 # main_navigation, home, booking(+success), active_queue,
                             #   history, profile, notification, sos (profile/notification
                             #   are shared with staff — import, don't duplicate)
    staff/                   # staff_navigation, queue, sos, history, availability
    admin/                   # admin_navigation, admin_users
functions/
  src/index.ts                # Cloud Functions (Node/TS, Admin SDK) — see "Cloud Functions" below
firestore.rules                # security rules — appointments only let a patient cancel their
                               #   OWN 'กำลังรอ' doc; staff-account creation and queue-offer
                               #   responses go through callable functions, not direct client writes
```

Layering rule: Firestore queries/writes live in `services/`, pure logic in `core/`, UI state (StreamBuilder/setState/snackbars) in `features/`. A few deliberate import cycles exist (e.g. profile_screen → app.dart for AuthGate) — legal in Dart, don't add indirection to remove them.

### Tech Stack
- **Firebase Auth** — email/password authentication
- **Cloud Firestore** — real-time database (no local state persistence)
- **Cloud Functions** (`functions/`, Node 22 + TypeScript) — all push notifications + the callable functions listed above; deployed separately from the Flutter app, see Commands
- **cloud_functions** (Flutter package) — client-side callable invocation (`noshow_offer_service.dart`, `staff_invite_service.dart`)
- **firebase_app_check** — activated in `main.dart` (Play Integrity in release, debug provider when `kDebugMode`); every `onCall` function sets `enforceAppCheck: true`, so callables already reject requests without a valid token. **Firestore itself is NOT yet enforced** — that's a manual toggle in Firebase Console → App Check → APIs (do it only after confirming Play Integrity attestation works for real release builds, or every client gets locked out).
- **Google Fonts** — `notoSansThai` for Thai UI, `playfairDisplay` for branding, `prompt` for queue numbers
- **image_picker** — profile photos (stored as base64, not Storage URLs)
- **Material 3** — UI with green (`#186B44`) color scheme

### Global Colors & Theme

Defined in `lib/core/theme.dart`, used everywhere:
```dart
const Color primaryGreen = Color(0xff186B44);
const Color lightGreen   = Color(0xffE6F4EA);
const Color bgWhite      = Color(0xffF7FCF9);
const Color textDark     = Color(0xff2D312F);
// Standard gradient for icons/buttons:
// [Color(0xff1b4332), Color(0xff52b788)] topLeft→bottomRight
```
Use `.withValues(alpha: ...)` instead of the deprecated `.withOpacity(...)`.

### Role Separation

`AuthGate` listens to `FirebaseAuth.instance.authStateChanges()` and reads the `role` field from `users/{uid}` to route:

| Role | Navigation Root | Tabs |
|---|---|---|
| `patient` | `MainNavigation` | หน้าแรก, คิวของฉัน, ประวัติ, โปรไฟล์ |
| `staff` | `StaffNavigation` | จัดการคิว, SOS, ประวัติการรักษา, เวลาว่าง, โปรไฟล์ |
| `admin` | `AdminNavigation` | จัดการผู้ใช้ (`AdminUsersScreen` only, so far) |

### Firestore Collections

| Collection | Purpose | Key Fields |
|---|---|---|
| `users` | Patient/staff/admin profiles | `uid`, `fullname`, `email`, `role`, `photoBase64`, `fcmTokens: List<String>`, `createdAt`. **Patient signup defers this doc entirely**: `register_screen.dart` creates the Firebase Auth account + sets `displayName` + sends the verification email, but does NOT write `users/{uid}` — `AuthGate` (`app/app.dart`) treats a missing doc as "patient mid-verification" and shows `_EmailVerificationGate`, which writes the doc (role: patient, fullname from `displayName`) only once `emailVerified` is confirmed true. An abandoned/never-verified signup therefore leaves no Firestore data at all. Staff signup is NOT deferred — `redeemStaffInvite` writes the doc immediately (the invite code is already a stronger gate than public patient signup, and deferring would leave a burned code in limbo). |
| `appointments` | Queue bookings | `patientUid`, `patientName`, `queueNo`, `doctor`, `staffUid`, `date`, `time`, `status`, `machineId`, `machineName`, `notes`, `createdAt`, `updatedAt`; optional cancel fields `cancelledAt`/`cancelledBy`; optional `noShowOffer*` fields — see below |
| `queue_days` | Daily queue-number counter, shared across ALL staff | doc ID = sanitized date (`dd-MM-yyyy`), fields: `date`, `count` — only ever incremented inside `createBooking`'s transaction; nothing else may touch this |
| `queue_slots` | Per-staff time-slot locks | doc ID = `{staffUid}_{dateKey}`, fields: `staffUid`, `date`, `bookedTimes: {time: apptId \| false}` |
| `sos_alerts` | Emergency alerts | `patientUid`, `patientName`, `issue`, `status`, `createdAt`, `resolvedAt` |
| `staff_availability` | Staff working hours | doc ID = `{staffUid}_{date}`, fields: `staffUid`, `date`, `times: List<String>`, `updatedAt` |
| `machine_status` | ESP32 heartbeat (per machine) | doc ID = machine ID (e.g. `current`), fields: `is_active: bool`, `last_updated: Timestamp` |
| `settings/staff_invite` | Invite code required during staff registration | admin-only read/write; redeemed exclusively via the `redeemStaffInvite` callable (Admin SDK), never read directly by clients |
| `notifications` | FCM send history + client-side unread list | doc ID is deterministic per logical event (dedupe — see Cloud Functions section), fields: `uid`, `type`, `title`, `body`, `refId`, `read`, `createdAt`, `expiresAt` |

**Auto-cancel + "come in earlier?" offer fields on `appointments`** (written only by `functions/src/index.ts`'s `checkLateAppointments` / its `cancelAppointmentAndOfferNext` helper — never by the Flutter app directly). Two independent staleness triggers, both handled by the SAME code path: (1) a `กำลังรอ` appointment past its own scheduled time by 5+ min (`cancelledBy: 'system_late'`), (2) a `เรียกคิว` appointment whose `updatedAt` is 10+ min stale, i.e. called but never checked in (`cancelledBy: 'system_noshow'`). **Both auto-cancel the appointment unconditionally** (`status: 'ยกเลิก'`, regardless of whether a next patient exists to notify) — routed through the normal `onBookingCancelled` trigger for notifications, and `autoCallNextOnComplete` still mechanically advances the queue as usual. Separately (if a same-staff waiting candidate exists), that next patient gets `noShowOfferStatus` (`'pending'|'accepted'|'declined'`) / `noShowOfferOptions` (two `HH:MM` arrival-time choices, `now+5min`/`now+10min`) / `noShowOfferFromApptId` / `noShowOfferSentAt` / `noShowOfferExpiresAt` / `noShowOfferChosenTime` — a courtesy nudge with **no queueNo/time reordering at all**; no response within 5 min auto-resolves to `'declined'`. Accept/decline via the `respondToNoShowOffer` callable (`noshow_offer_service.dart`), rendered by `NoShowOfferBanner` (`core/widgets.dart`) on `HomeScreen`/`ActiveQueueScreen` — driven by the existing Firestore stream, not by FCM (push is a wake-up nudge only, never the source of truth). `noShowOfferChosenTime` is surfaced to staff as a small chip on the queue card, informational only. (An earlier design swapped `queueNo`/`time` between the late and next patient via a `respondToEarlyOffer` callable — retired in favor of this simpler unconditional-cancel-plus-nudge model; don't resurrect `earlyOfferStatus`/`lateFlaggedAt` fields if you see them referenced in old commits.)

### Queue Status Flow

`กำลังรอ` (waiting) → `เรียกคิว` (called) → `กำลังรักษา` (treating) → `เสร็จสิ้น` (completed), plus a cancelled state. SOS alerts have separate pending/resolved states.

Status strings are stored verbatim as Thai text in Firestore — use the `QueueStatus`/`SosStatus` constants from `lib/core/status.dart` instead of retyping literals, and never change the constant values. (One literal filter-chip list remains in `staff_queue_screen.dart` because its shape — `''` + no cancelled — matches no constant.)

Controlled by staff in `StaffQueueScreen`. Patients see real-time updates via Firestore streams in `ActiveQueueScreen` and `HomeScreen`. Sorting is done **client-side** (by `createdAt`) to avoid Firestore composite index requirements — be careful before adding chained `where`/`orderBy` queries, since they may require a new index.

**Queue advancement is automatic, with a conditional manual recovery banner.** `functions/src/index.ts`'s `autoCallNextOnComplete` (Firestore trigger) fires when a slot frees up (status → `เสร็จสิ้น`, or a called/treating appointment gets cancelled) and auto-calls the earliest-`queueNo` still-`กำลังรอ` appointment for that same `staffUid`+`date` inside a transaction that re-validates the candidate's status first — this is also the idempotency guard against Cloud Functions' at-least-once trigger delivery, so don't replace it with a plain `.update()`. It only fires on a status *transition*, so it never kicks off the very first patient of a fresh queue — `StaffQueueScreen` shows an amber recovery banner with a manual "เรียกคิว" button (`_callNext()`) whenever `waiting > 0 && calling == 0 && treating == 0` on today's board, covering both that cold-start case and any silent Cloud Function failure. Per-card manual "เรียกคิว" buttons on individual queue cards also still exist as a staff override (e.g. to skip order deliberately) — those go through `_changeStatus()` directly.

### Key Widgets & Helpers

- **`icon3D(IconData, List<Color>, double size)`** (`core/widgets.dart`) — gradient container + double BoxShadow + shine overlay, used for action/service card icons. (`StaffSOSScreen` has its own private `_sosIcon3D` — a different implementation, kept separate on purpose.)
- **`MachineStatusCard(machineId, machineName)`** (`core/widgets.dart`) — StreamBuilder on `machine_status/{machineId}`; marks stale via `isMachineStale` (`core/format.dart`, 30s ESP32 heartbeat timeout). Appointments reference a specific machine via `machineId`/`machineName`.
- **Doc-ID builders** — both `AvailabilityService.docId` and `QueueSlotService.docId` sanitize `/`→`-` in the date (e.g. `abc123_21-06-2569`). This is required, not stylistic: a literal `/` passed into `.doc(path)` is a path separator to the Firestore SDK, not a character, so an unsanitized date silently nests the write into a subcollection and falls outside the flat `staff_availability/{id}` / `queue_slots/{id}` security rules (was a real bug — PERMISSION_DENIED regardless of auth). Both use direct `.doc(id).get()` lookups to avoid composite indexes.
- **Booking** — `AppointmentService.createBooking` runs the day-counter + slot-lock + appointment transaction and returns a sealed `BookingOutcome` (`BookingSuccess`/`BookingBlockedByActiveQueue`/`BookingFailed`); snackbars/navigation stay in `BookingScreen`.
- **Profile photos** — base64 strings in `users/{uid}.photoBase64`; use `core/photo.dart` (`tryDecodePhotoBase64` → `MemoryImage`). No Firebase Storage is used.
- **FCM** — `services/fcm_service.dart` owns token lifecycle + the pure `notificationDestination(role, type)` table; widget mapping lives in `app/app.dart` (`routeFromNotification`). Actual sending happens server-side in `functions/src/index.ts` — this file only handles the client token and routing a tap once a push has already arrived.
- **`NoShowOfferBanner`** (`core/widgets.dart`) — shown on `HomeScreen`/`ActiveQueueScreen` when a patient's own appointment has `noShowOfferStatus == 'pending'`; accept/decline both go through `noshow_offer_service.dart`'s callable wrapper, never a direct Firestore write.
- **Self-service account deletion** (PDPA right-to-erasure) — `ProfileScreen`, patient-only. Requires password re-authentication (`reauthenticateWithCredential`) before calling `UserService.deleteOwnAccount(uid)` (deletes `users/{uid}` + the patient's own `appointments` only — never `staff_availability` or appointments where they're only the `staffUid`) then `user.delete()`. Distinct from admin's `deleteUserCascade` (broader, admin-only, used by `AdminUsersScreen` to remove any account including cascading staff-linked appointments). `firestore.rules` enforces the same narrow scope server-side — don't widen `deleteOwnAccount`'s query without widening the matching rule first.

### Assets

- `assets/hart.png` — logo (used in place of `Icons.favorite_rounded` everywhere)
- `assets/Log1.1.png` — hospital building image shown in queue cards
- Registered via a wildcard `assets/` entry in `pubspec.yaml`

### Thai Language

All UI strings and code comments are in Thai. Keep user-facing strings in Thai unless a task specifically asks otherwise.

## Editing Guidance

- Keep the layering: Firestore/FCM I/O in `services/`, pure logic in `core/`, UI in `features/`. Don't put queries in widgets or widgets in services.
- Services take `{FirebaseFirestore? db}` defaulting to `.instance` — preserve this so tests can inject `fake_cloud_firestore`.
- Match the surrounding style (Thai comments, compact widget builders); prefer small, focused edits.
- Do not commit secrets or regenerate Firebase config (`flutterfire configure`, `google-services.json`) unless that is the explicit task.
