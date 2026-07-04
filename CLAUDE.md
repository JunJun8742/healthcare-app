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

# Run tests (no test/ directory currently exists; note this if asked to run tests)
flutter test

# Build release APK (shared manually, e.g. via Line/Drive)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Regenerate Firebase options (requires flutterfire CLI) — only when explicitly asked
flutterfire configure
```

There is no single-test runner since there's no `test/` suite yet — `flutter analyze` is the primary verification step after Dart changes.

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
    sos_service.dart / user_service.dart / notification_service.dart
  features/
    auth/                    # login, register, staff_register
    patient/                 # main_navigation, home, booking(+success), active_queue,
                             #   history, profile, notification, sos (profile/notification
                             #   are shared with staff — import, don't duplicate)
    staff/                   # staff_navigation, queue, sos, history, availability
    admin/                   # admin_navigation, admin_users
```

Layering rule: Firestore queries/writes live in `services/`, pure logic in `core/`, UI state (StreamBuilder/setState/snackbars) in `features/`. A few deliberate import cycles exist (e.g. profile_screen → app.dart for AuthGate) — legal in Dart, don't add indirection to remove them.

### Tech Stack
- **Firebase Auth** — email/password authentication
- **Cloud Firestore** — real-time database (no local state persistence)
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
| `users` | Patient/staff/admin profiles | `uid`, `fullname`, `email`, `role`, `photoBase64`, `createdAt` |
| `appointments` | Queue bookings | `patientUid`, `patientName`, `queueNo`, `doctor`, `staffUid`, `date`, `time`, `status`, `machineId`, `machineName`, `notes`, `createdAt` |
| `sos_alerts` | Emergency alerts | `patientUid`, `patientName`, `issue`, `status`, `createdAt`, `resolvedAt` |
| `staff_availability` | Staff working hours | doc ID = `{staffUid}_{date}`, fields: `staffUid`, `date`, `times: List<String>`, `updatedAt` |
| `machine_status` | ESP32 heartbeat (per machine) | doc ID = machine ID (e.g. `current`), fields: `is_active: bool`, `last_updated: Timestamp` |
| `settings/staff_invite` | Invite code required during staff registration | invite code field checked at signup |

### Queue Status Flow

`กำลังรอ` (waiting) → `เรียกคิว` (called) → `กำลังรักษา` (treating) → `เสร็จสิ้น` (completed), plus a cancelled state. SOS alerts have separate pending/resolved states.

Status strings are stored verbatim as Thai text in Firestore — use the `QueueStatus`/`SosStatus` constants from `lib/core/status.dart` instead of retyping literals, and never change the constant values. (One literal filter-chip list remains in `staff_queue_screen.dart` because its shape — `''` + no cancelled — matches no constant.)

Controlled by staff in `StaffQueueScreen`. Patients see real-time updates via Firestore streams in `ActiveQueueScreen` and `HomeScreen`. Sorting is done **client-side** (by `createdAt`) to avoid Firestore composite index requirements — be careful before adding chained `where`/`orderBy` queries, since they may require a new index.

### Key Widgets & Helpers

- **`icon3D(IconData, List<Color>, double size)`** (`core/widgets.dart`) — gradient container + double BoxShadow + shine overlay, used for action/service card icons. (`StaffSOSScreen` has its own private `_sosIcon3D` — a different implementation, kept separate on purpose.)
- **`MachineStatusCard(machineId, machineName)`** (`core/widgets.dart`) — StreamBuilder on `machine_status/{machineId}`; marks stale via `isMachineStale` (`core/format.dart`, 30s ESP32 heartbeat timeout). Appointments reference a specific machine via `machineId`/`machineName`.
- **Doc-ID builders** — `AvailabilityService.docId` keeps the raw Thai date (`abc123_21/06/2569`); `QueueSlotService.docId` sanitizes `/`→`-`. Both use direct `.doc(id).get()` lookups to avoid composite indexes. Don't unify them — the stored data depends on each format.
- **Booking** — `AppointmentService.createBooking` runs the day-counter + slot-lock + appointment transaction and returns a sealed `BookingOutcome` (`BookingSuccess`/`BookingBlockedByActiveQueue`/`BookingFailed`); snackbars/navigation stay in `BookingScreen`.
- **Profile photos** — base64 strings in `users/{uid}.photoBase64`; use `core/photo.dart` (`tryDecodePhotoBase64` → `MemoryImage`). No Firebase Storage is used.
- **FCM** — `services/fcm_service.dart` owns token lifecycle + the pure `notificationDestination(role, type)` table; widget mapping lives in `app/app.dart` (`routeFromNotification`).

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
