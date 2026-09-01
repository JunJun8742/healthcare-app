import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:healthcare_app/app/app.dart';
import 'package:healthcare_app/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Debug provider in debug builds (register the printed token in Firebase
  // Console > App Check > "Manage debug tokens" to pass local testing);
  // Play Integrity in release. Never throw — App Check attests requests to
  // Firestore/Functions but must not block app startup if it fails to init.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
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
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await initFcmBootstrap(onNotificationTap: routeFromNotification);
  runZonedGuarded(
    () => runApp(const HealthcareStation()),
    (error, stack) =>
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
  );
}
