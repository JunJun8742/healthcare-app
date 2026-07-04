import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/appointment_service.dart';

// ==========================================
// 8. History Screen (Patient) — เลือกวันได้
// ==========================================
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  void _showDetail(BuildContext ctx, Map<String, dynamic> data) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.medical_services, color: primaryGreen), const SizedBox(width: 10), Text('คิว ${data['queueNo'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold))]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.local_hospital, 'นักกายภาพ', data['doctor'] ?? '-'),
          _row(Icons.calendar_today, 'วันที่', data['date'] ?? '-'),
          _row(Icons.access_time, 'เวลา', data['time'] ?? '-'),
          _row(Icons.computer_rounded, 'เครื่อง', (data['machineName'] ?? '').toString().isNotEmpty ? data['machineName'] : '-'),
          _row(Icons.info_outline, 'สถานะ', data['status'] ?? '-'),
          if ((data['notes'] ?? '').toString().isNotEmpty) _row(Icons.note_alt_outlined, 'บันทึกจากเจ้าหน้าที่', data['notes']),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด', style: TextStyle(color: primaryGreen)))],
      ),
    );
  }

  Widget _row(IconData icon, String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: primaryGreen), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14, color: textSecondary)),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w600, color: textDark)),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติการรักษา')),
      body: StreamBuilder<QuerySnapshot>(
        stream: appointments.patientAppointments(user?.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
          }
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const StateMessage(icon: Icons.history_toggle_off_rounded, message: 'ยังไม่มีประวัติ');
          }
          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
          return ListView.builder(
            padding: const EdgeInsets.all(16), itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              String status = data['status'] ?? 'กำลังรอ';
              final s = statusInfo(status);
              Color sc = s.color;
              bool isCancelled = status == 'ยกเลิก';
              return GestureDetector(
                onTap: () => _showDetail(context, data),
                child: Opacity(
                  opacity: isCancelled ? 0.6 : 1.0,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
                      border: Border(left: BorderSide(color: sc, width: 4)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(s.icon, color: sc, size: 18)),
                            const SizedBox(width: 10),
                            Text('คิว ${data['queueNo'] ?? '-'}', style: GoogleFonts.prompt(fontWeight: FontWeight.bold, fontSize: 17, color: textDark)),
                          ]),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text(s.label, style: GoogleFonts.notoSansThai(color: sc, fontWeight: FontWeight.bold, fontSize: 14))),
                        ]),
                        const SizedBox(height: 8),
                        Text(data['doctor'] ?? '-', style: GoogleFonts.notoSansThai(color: textDark, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.calendar_today, size: 13, color: textSecondary), const SizedBox(width: 4),
                          Text(data['date'] ?? '', style: TextStyle(color: textSecondary, fontSize: 14)),
                          const SizedBox(width: 12),
                          Icon(Icons.access_time, size: 13, color: textSecondary), const SizedBox(width: 4),
                          Text(data['time'] ?? '', style: TextStyle(color: textSecondary, fontSize: 14)),
                          if ((data['machineName'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.computer_rounded, size: 13, color: textSecondary), const SizedBox(width: 4),
                            Expanded(child: Text(data['machineName'], style: TextStyle(color: textSecondary, fontSize: 14), overflow: TextOverflow.ellipsis)),
                          ],
                        ]),
                        if ((data['notes'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(8)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.note_alt_outlined, size: 14, color: primaryGreen), const SizedBox(width: 6), Expanded(child: Text(data['notes'], style: const TextStyle(fontSize: 14, color: primaryGreen)))])),
                        ],
                      ]),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
