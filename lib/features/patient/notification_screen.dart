import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/notification_service.dart';

// ==========================================
// 10. Notification Screen
// ==========================================
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  // ไอคอน + สีต่อประเภทแจ้งเตือน
  ({IconData icon, Color color}) _styleFor(String type) {
    switch (type) {
      case 'queue_called':
        return (icon: Icons.campaign_rounded, color: primaryGreen);
      case 'sos_new':
        return (icon: Icons.sos_rounded, color: Colors.red);
      case 'booking_created':
        return (icon: Icons.event_available_rounded, color: primaryGreen);
      case 'booking_cancelled':
        return (icon: Icons.event_busy_rounded, color: Colors.orange);
      case 'morning_reminder':
        return (icon: Icons.alarm_rounded, color: Colors.amber.shade800);
      default:
        return (icon: Icons.notifications_rounded, color: Colors.grey);
    }
  }

  // เวลาแบบสัมพัทธ์ (ภาษาไทย)
  String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';
  }

  Widget _card(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = (data['type'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final body = (data['body'] ?? '').toString();
    final read = data['read'] == true;
    final s = _styleFor(type);
    return GestureDetector(
      onTap: read ? null : () => notifications.markRead(doc.reference).catchError((e) => debugPrint('mark notification read failed: $e')),
      child: Container(
        margin: const EdgeInsets.only(bottom: kGapM),
        padding: const EdgeInsets.all(kCardPadding),
        decoration: BoxDecoration(
          color: read ? Colors.white : lightGreen,
          borderRadius: BorderRadius.circular(kRadius),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: s.color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(s.icon, color: s.color, size: 22),
          ),
          const SizedBox(width: kGapM),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (!read) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: const BoxDecoration(color: primaryGreen, shape: BoxShape.circle)),
              Expanded(child: Text(title, style: tBody().copyWith(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            Text(body, style: tBody(textSecondary)),
          ])),
          const SizedBox(width: kGapS),
          Text(_relativeTime(data['createdAt'] as Timestamp?), style: tCaption()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน')),
      body: StreamBuilder<QuerySnapshot>(
        stream: notifications.forUser(FirebaseAuth.instance.currentUser?.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryGreen));
          }
          if (snap.hasError) {
            return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
          }
          var docs = (snap.data?.docs ?? []).toList()
            ..sort((a, b) {
              final ta = a['createdAt'] as Timestamp?;
              final tb = b['createdAt'] as Timestamp?;
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });
          if (docs.isEmpty) {
            return const StateMessage(icon: Icons.notifications_off_rounded, message: 'ยังไม่มีการแจ้งเตือน');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(kGapL),
            itemCount: docs.length,
            itemBuilder: (_, i) => _card(docs[i]),
          );
        },
      ),
    );
  }
}
