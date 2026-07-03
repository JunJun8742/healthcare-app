# Repository Guidelines

## Project Overview

This is a Flutter healthcare queue app. The UI is Thai-first and uses Firebase for authentication and real-time data.

The application is intentionally concentrated in `lib/main.dart`; keep changes compatible with that single-file structure unless the task explicitly calls for a broader refactor.

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

- `lib/main.dart`: main app, screens, routing, Firestore calls, helpers, and theme constants.
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

Global colors are defined near the top of `lib/main.dart`:

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

Queue and SOS status strings are stored as Thai UI text, so preserve the exact values already present in `lib/main.dart` when changing logic. Search for the status comparisons in `HomeScreen`, `ActiveQueueScreen`, `StaffQueueScreen`, and `StaffSOSScreen` before editing any status flow.

The active queue flow is:

```text
waiting -> called -> treating -> completed
```

There is also a cancelled queue state and pending/resolved SOS states, all represented by Thai strings in Firestore.

Sorting is often done client-side by `createdAt` to avoid extra Firestore composite indexes. Be careful before adding chained Firestore `where`/`orderBy` queries that may require new indexes.

## Date And Availability Notes

- Staff availability document IDs are built as `${staffUid}_${dateStr}`.
- Date strings in the current UI use Thai/Buddhist-year display format in parts of the staff availability flow.
- Booking logic reads availability by direct document ID lookup where possible.

## Testing And Verification

After Dart changes, run:

```bash
flutter analyze
```

Run `flutter test` when behavior changes or when adding tests. This repository may not always include a populated `test/` directory, so note that clearly if tests cannot be run meaningfully.

## Editing Guidance

- Prefer small, focused edits in `lib/main.dart` that match the surrounding style.
- Keep user-facing strings in Thai unless a task specifically asks otherwise.
- Avoid broad file splitting or architecture changes unless requested.
- Do not commit secrets or regenerate Firebase config unless that is the requested task.
- Profile photos are stored as base64 strings in Firestore and rendered with `MemoryImage(base64Decode(...))`.
