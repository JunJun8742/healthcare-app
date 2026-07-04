import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:healthcare_app/app/app.dart';
import 'package:healthcare_app/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initFcmBootstrap(onNotificationTap: routeFromNotification);
  runApp(const HealthcareStation());
}
