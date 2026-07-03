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

This is a **single-file Flutter app** — the entire application (screens, models, routing, Firestore calls, theme) lives in [`lib/main.dart`](lib/main.dart) (~3200 lines). There are no separate files for screens/models/services. Keep changes compatible with this single-file structure unless a task explicitly calls for a broader refactor.

### Tech Stack
- **Firebase Auth** — email/password authentication
- **Cloud Firestore** — real-time database (no local state persistence)
- **Google Fonts** — `notoSansThai` for Thai UI, `playfairDisplay` for branding, `prompt` for queue numbers
- **image_picker** — profile photos (stored as base64, not Storage URLs)
- **Material 3** — UI with green (`#186B44`) color scheme

### Global Colors & Theme

Defined near the top of `main.dart`, used everywhere:
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

Status strings are stored verbatim as Thai text in Firestore — preserve exact values when editing logic. Search for status comparisons in `HomeScreen`, `ActiveQueueScreen`, `StaffQueueScreen`, and `StaffSOSScreen` before changing any status flow.

Controlled by staff in `StaffQueueScreen`. Patients see real-time updates via Firestore streams in `ActiveQueueScreen` and `HomeScreen`. Sorting is done **client-side** (by `createdAt`) to avoid Firestore composite index requirements — be careful before adding chained `where`/`orderBy` queries, since they may require a new index.

### Key Widgets & Helpers

- **`_icon3D(IconData, List<Color>, double size)`** — gradient container + double BoxShadow + shine overlay. Used for all action/service card icons.
- **`MachineStatusCard(machineId, machineName)`** — StreamBuilder on `machine_status/{machineId}`; marks stale if `last_updated` is more than 30 seconds old (ESP32 heartbeat timeout). Appointments reference a specific machine via `machineId`/`machineName`.
- **`staff_availability` doc ID** — always `${staffUid}_${dateStr}` (e.g. `abc123_2024-06-21`). Use `.doc(docId).get()` directly to avoid a composite index.
- **Profile photos** — stored as base64 strings in `users/{uid}.photoBase64`, rendered with `MemoryImage(base64Decode(photoBase64))`. No Firebase Storage is used.
- **Date/availability** — some staff-availability UI displays dates in Thai/Buddhist-year format; booking logic reads availability by direct document ID lookup where possible.

### Assets

- `assets/hart.png` — logo (used in place of `Icons.favorite_rounded` everywhere)
- `assets/Log1.1.png` — hospital building image shown in queue cards
- Registered via a wildcard `assets/` entry in `pubspec.yaml`

### Thai Language

All UI strings and code comments are in Thai. Keep user-facing strings in Thai unless a task specifically asks otherwise.

## Editing Guidance

- Prefer small, focused edits in `lib/main.dart` that match the surrounding style; avoid broad file splitting or architecture changes unless requested.
- Do not commit secrets or regenerate Firebase config (`flutterfire configure`, `google-services.json`) unless that is the explicit task.
