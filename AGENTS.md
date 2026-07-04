# Repository Guidelines

## Project Overview

This is a Flutter healthcare queue app. The UI is Thai-first and uses Firebase for authentication and real-time data.

The app is split by feature with an extracted service/logic layer (Dart package name: `healthcare_app`):

```text
lib/
  main.dart                  # bootstrap only: Firebase init + FCM bootstrap + runApp
  app/app.dart               # HealthcareStation (MaterialApp), AuthGate, notification routing
  core/                      # theme.dart, status.dart (QueueStatus/SosStatus + statusInfo),
                             # format.dart (Thai dates, comparators), photo.dart (base64), widgets.dart
  services/                  # Firestore/FCM I/O behind classes with injectable {FirebaseFirestore? db}
                             # fcm, queue_slot, availability, appointment, sos, user, notification
  features/                  # screens by role: auth/, patient/, staff/, admin/
```

Services own Firestore I/O; screens own UI state (StreamBuilder/setState/snackbars). Each service file ends with a shared default instance (e.g. `final SosService sos = SosService();`). Use absolute `package:healthcare_app/...` imports.

## Common Commands

Run these from `healthcare-app/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Release APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Firebase options can be regenerated with:

```bash
flutterfire configure
```

## Tech Stack

- Flutter with Material 3.
- Firebase Auth for email/password sign-in.
- Cloud Firestore for all app data.
- Google Fonts: Prompt, Noto Sans Thai, and Playfair Display.
- `image_picker` for profile photos.

## Important Files

- `lib/app/app.dart`: MaterialApp root, `AuthGate` role routing, notification tap routing.
- `lib/core/status.dart`: `QueueStatus`/`SosStatus` constants (exact Firestore values) + `statusInfo()`.
- `lib/services/appointment_service.dart`: booking transaction and typed `BookingOutcome`.
- `lib/firebase_options.dart`: generated Firebase configuration.
- `pubspec.yaml`: dependencies and asset registration.
- `assets/hart.png`: heart/logo asset used instead of favorite icons.
- `assets/Log1.1.png`: hospital image used in queue cards.
- `android/app/google-services.json`: Android Firebase config.

## Architecture Notes

- `main()` initializes Firebase, then starts `HealthcareStation`.
- `AuthGate` listens to `FirebaseAuth.instance.authStateChanges()` and routes by `users/{uid}.role`.
- Roles:
  - `patient`: `MainNavigation`
  - `staff`: `StaffNavigation`
  - `admin`: `AdminNavigation`
- Patient tabs: home, active queue, history, profile.
- Staff tabs: queue management, SOS, treatment history, availability, profile.
- Admin currently manages users in `AdminUsersScreen`.

## Theme And UI Conventions

Global colors are defined in `lib/core/theme.dart`:

```dart
const Color primaryGreen = Color(0xff186B44);
const Color lightGreen = Color(0xffE6F4EA);
const Color bgWhite = Color(0xffF7FCF9);
const Color textDark = Color(0xff2D312F);
```

Keep the green healthcare visual language consistent. The app commonly uses rounded white panels, subtle green shadows, Thai text, and Material icons. Use `withValues(alpha: ...)` instead of deprecated opacity helpers.

## Firestore Collections

- `users`: profile and role data. Important fields include `uid`, `fullname`, `email`, `role`, `photoBase64`, and `createdAt`.
- `appointments`: queue bookings. Important fields include `patientUid`, `patientName`, `queueNo`, `doctor`, `staffUid`, `date`, `time`, `status`, `machineId`, `machineName`, `notes`, and timestamps.
- `sos_alerts`: emergency alerts with `patientUid`, `patientName`, `issue`, `status`, `createdAt`, and `resolvedAt`.
- `staff_availability`: staff working hours. Document ID format is `{staffUid}_{date}` and fields include `staffUid`, `date`, `times`, and `updatedAt`.
- `machine_status`: ESP32/machine heartbeat data. Documents include `is_active` and `last_updated`; `MachineStatusCard` treats data older than 30 seconds as stale.
- `settings/staff_invite`: invite code used during staff registration.

## Queue And Status Conventions

Queue and SOS status strings are stored as Thai text in Firestore. Use the `QueueStatus`/`SosStatus` constants from `lib/core/status.dart` — never retype the literals, and never change the constant values.

The active queue flow is:

```text
waiting -> called -> treating -> completed
```

There is also a cancelled queue state and pending/resolved SOS states, all represented by Thai strings in Firestore.

Sorting is often done client-side by `createdAt` to avoid extra Firestore composite indexes. Be careful before adding chained Firestore `where`/`orderBy` queries that may require new indexes.

## Date And Availability Notes

- Staff availability document IDs are built as `${staffUid}_${dateStr}` (raw Thai date, `/` intact — see `AvailabilityService.docId`); `queue_slots` IDs sanitize `/`→`-` (see `QueueSlotService.docId`).
- Date strings in the current UI use Thai/Buddhist-year display format in parts of the staff availability flow.
- Booking logic reads availability by direct document ID lookup where possible.

## Testing And Verification

After Dart changes, run:

```bash
flutter analyze
```

Run `flutter test` when behavior changes or when adding tests. This repository may not always include a populated `test/` directory, so note that clearly if tests cannot be run meaningfully.

## Editing Guidance

- Keep the layering: Firestore/FCM I/O in `lib/services/`, pure logic in `lib/core/`, UI in `lib/features/`. Don't put queries in widgets.
- Services take `{FirebaseFirestore? db}` (default `.instance`) so tests can inject `fake_cloud_firestore` — preserve that pattern in new methods.
- Keep user-facing strings in Thai unless a task specifically asks otherwise.
- Do not commit secrets or regenerate Firebase config unless that is the requested task.
- Profile photos are stored as base64 strings in Firestore; use `core/photo.dart` helpers (`encodePhotoBase64`/`tryDecodePhotoBase64`).
