import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:healthcare_app/app/app.dart';
import 'package:healthcare_app/services/fcm_service.dart';

// App Check debug token — FIXED on purpose (not left to auto-generate) so
// every debug build on every dev device presents the SAME token, and this
// ONE value gets registered ONCE in Firebase Console > App Check > Manage
// debug tokens, instead of every fresh emulator/device needing its own
// registration. Debug-only: release builds use Play Integrity, never this.
// Not a secret in the security sense (App Check debug tokens are meant to be
// a known value for controlled dev/CI devices) — still, don't reuse this
// constant for anything outside local development.
const String _appCheckDebugToken = '436c7784-73e0-4cec-8bc4-3bd3c6a2a45b';

// WidgetsFlutterBinding.ensureInitialized() and runApp() must run in the SAME
// zone — Flutter asserts this at startup ("Zone mismatch") and it's not just
// a cosmetic warning: mismatched zones make zone-scoped state (this Crashlytics
// error handler included) inconsistently apply. So the whole bootstrap — not
// just runApp — lives inside the one runZonedGuarded callback below.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
    // Debug provider in debug builds (register the printed token in Firebase
    // Console > App Check > "Manage debug tokens" to pass local testing);
    // Play Integrity in release. Never throw — App Check attests requests to
    // Firestore/Functions but must not block app startup if it fails to init.
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider(debugToken: _appCheckDebugToken)
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (e) {
      debugPrint('App Check activate error: $e');
    }

    // Crash reporting — off in debug builds so local dev noise never reaches
    // the dashboard (matches CLAUDE.md convention of debugPrint for dev-only
    // errors). Flutter framework errors AND uncaught async/platform errors
    // outside the Flutter framework are both routed to Crashlytics; runZoned
    // catches the latter (PlatformDispatcher.onError alone misses some Dart
    // isolate errors on older engines).
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    await initFcmBootstrap(onNotificationTap: routeFromNotification);
    runApp(const HealthcareStation());
  }, (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack, fatal: true));
}
