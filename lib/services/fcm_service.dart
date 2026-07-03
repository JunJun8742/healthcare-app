import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ==========================================
// Push notifications: FCM token lifecycle + session state
// ==========================================
final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
String? pendingNotifType; // ประเภทแจ้งเตือนที่แตะจากสถานะปิดแอป — ใช้ครั้งเดียวตอน AuthGate สร้างหน้าแรก
String? currentUserRole;
bool _fcmRegistered = false;
bool _fcmListenersAttached = false;

bool get fcmRegistered => _fcmRegistered;
void resetFcmRegistration() => _fcmRegistered = false;

/// ปลายทางที่จะเปิดเมื่อผู้ใช้แตะแจ้งเตือน ตามบทบาทผู้ใช้ + ประเภทแจ้งเตือน
/// (ตารางตัดสินใจล้วน ๆ — ฝั่ง widget เป็นคนแปลงเป็นหน้าจอจริง)
enum NotifDestination { patientQueue, staffQueue, staffSos }

NotifDestination? notificationDestination({required String? role, required String? type}) {
  if (type == null) return null;
  const patientTargets = {'queue_called', 'morning_reminder', 'booking_cancelled'};
  const staffQueueTargets = {'booking_created', 'booking_cancelled'};
  if (role == 'patient' && patientTargets.contains(type)) return NotifDestination.patientQueue;
  if (role == 'staff' && type == 'sos_new') return NotifDestination.staffSos;
  if (role == 'staff' && staffQueueTargets.contains(type)) return NotifDestination.staffQueue;
  return null;
}

/// ตั้งค่า local notifications + ช่องแจ้งเตือน + อ่าน getInitialMessage (แอปเปิดจากแจ้งเตือน)
/// ห้าม throw: ความล้มเหลวของระบบแจ้งเตือนต้องไม่ทำให้แอปเปิดไม่ได้
Future<void> initFcmBootstrap({required void Function(String? type) onNotificationTap}) async {
  try {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        try {
          final data = jsonDecode(resp.payload ?? '{}') as Map<String, dynamic>;
          onNotificationTap(data['type'] as String?);
        } catch (_) {}
      },
    );
    final androidPlugin = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel('healthcare_default', 'การแจ้งเตือนทั่วไป', importance: Importance.high));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel('sos_channel', 'แจ้งเตือนฉุกเฉิน SOS', importance: Importance.max));
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    pendingNotifType = initialMsg?.data['type'] as String?;
  } catch (e) {
    debugPrint('Notification init error: $e');
  }
}

// ลงทะเบียน FCM token ให้ users/{uid}.fcmTokens — เรียกครั้งเดียวต่อ session (กันซ้ำด้วย _fcmRegistered)
// ห้าม throw ออกไปนอกฟังก์ชันนี้เด็ดขาด: บน emulator ที่ไม่มี Play Services การขอ token จะ error
// ซึ่งต้องไม่ทำให้แอปเปิดไม่ได้
Future<void> registerFcm(String uid, {required void Function(String? type) onNotificationTap}) async {
  _fcmRegistered = true;
  try {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'fcmTokens': FieldValue.arrayUnion([token])}, SetOptions(merge: true));
    }
    if (!_fcmListenersAttached) {
      _fcmListenersAttached = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null) return;
        FirebaseFirestore.instance.collection('users').doc(currentUid).set({'fcmTokens': FieldValue.arrayUnion([newToken])}, SetOptions(merge: true));
      });
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        final type = message.data['type'];
        final isSos = type == 'sos_new';
        localNotifications.show(
          id: message.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(android: AndroidNotificationDetails(
            isSos ? 'sos_channel' : 'healthcare_default',
            isSos ? 'แจ้งเตือนฉุกเฉิน SOS' : 'การแจ้งเตือนทั่วไป',
            importance: isSos ? Importance.max : Importance.high,
            priority: isSos ? Priority.max : Priority.high,
          )),
          payload: jsonEncode({'type': type}),
        );
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        onNotificationTap(message.data['type'] as String?);
      });
    }
  } catch (e) {
    debugPrint('FCM register error: $e');
  }
}

// ลบ FCM token ก่อนออกจากระบบ — best-effort เท่านั้น ห้าม throw กันไม่ให้ logout ค้าง
Future<void> removeFcmTokenBeforeLogout() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmTokens': FieldValue.arrayRemove([token])});
    }
    await FirebaseMessaging.instance.deleteToken();
  } catch (e) {
    debugPrint('removeFcmTokenBeforeLogout error: $e');
  }
}
