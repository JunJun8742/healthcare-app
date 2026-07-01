# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app (choose target device)
flutter run

# Build release APK (send to another device via Line/Drive)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Analyze code (run after every edit)
flutter analyze

# Run tests
flutter test

# Regenerate Firebase options (requires flutterfire CLI)
flutterfire configure
```

## Architecture

This is a **single-file Flutter app** — the entire application lives in [`lib/main.dart`](lib/main.dart). There are no separate files for screens, models, or services.

### Tech Stack
- **Firebase Auth** — email/password authentication
- **Cloud Firestore** — real-time database (no local state persistence)
- **Google Fonts** — `notoSansThai` for Thai UI, `playfairDisplay` for branding, `prompt` for queue numbers
- **Material 3** — UI with green (`#186B44`) color scheme

### Global Colors & Theme

Defined at top of `main.dart`, used everywhere:
```dart
const Color primaryGreen = Color(0xff186B44);
const Color lightGreen   = Color(0xffE6F4EA);
const Color bgWhite      = Color(0xffF7FCF9);
const Color textDark     = Color(0xff2D312F);
// Standard gradient for icons/buttons:
// [Color(0xff1b4332), Color(0xff52b788)] topLeft→bottomRight
```

### Role Separation

Auth routing in `AuthGate`: reads `role` field from `users/{uid}` — if `role == 'staff'` → `StaffNavigation`, else → `MainNavigation`.

| Role | Navigation Root | Tabs |
|---|---|---|
| Patient | `MainNavigation` | หน้าแรก, คิวของฉัน, ประวัติ, โปรไฟล์ |
| Staff | `StaffNavigation` | จัดการคิว, SOS, ประวัติการรักษา, เวลาว่าง, โปรไฟล์ |

### Firestore Collections

| Collection | Purpose | Key Fields |
|---|---|---|
| `users` | Patient/staff profiles | `uid`, `fullname`, `email`, `role`, `photoBase64`, `createdAt` |
| `appointments` | Queue bookings | `patientUid`, `patientName`, `queueNo`, `doctor`, `staffUid`, `date`, `time`, `status`, `createdAt` |
| `sos_alerts` | Emergency alerts | `patientUid`, `patientName`, `issue`, `status`, `createdAt` |
| `staff_availability` | Staff working hours | doc ID = `{staffUid}_{date}`, fields: `staffUid`, `date`, `times: List<String>` |
| `machine_status` | ESP32 heartbeat | doc ID = `current`, fields: `is_active: bool`, `last_updated: Timestamp` |

### Queue Status Flow

`กำลังรอ` → `เรียกคิว` → `กำลังรักษา` → `เสร็จสิ้น`

Controlled by staff in `StaffQueueScreen`. Patient sees real-time updates via Firestore streams in `ActiveQueueScreen` and `HomeScreen`. Sorting is client-side (by `createdAt`) to avoid Firestore composite index requirements.

### Key Widgets & Helpers

- **`_icon3D(IconData, List<Color>, double size)`** — gradient container + double BoxShadow + shine overlay. Used for all action/service card icons.
- **`MachineStatusCard`** — StreamBuilder on `machine_status/current`; marks stale if `last_updated` > 30 seconds ago (ESP32 heartbeat timeout).
- **`staff_availability` doc ID** — always `${staffUid}_${dateStr}` (e.g. `abc123_2024-06-21`). Use `.doc(docId).get()` directly to avoid composite index.
- **Profile photos** — stored as base64 strings in `users/{uid}.photoBase64`, rendered with `MemoryImage(base64Decode(photoBase64))`.

### Assets

- `assets/hart.png` — logo (used in place of `Icons.favorite_rounded` everywhere)
- `assets/Log1.1.png` — hospital building image shown in queue cards
- Registered via `assets/` directory wildcard in `pubspec.yaml`

### Thai Language

All UI strings and code comments are in Thai.
