import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/appointment_service.dart';
import 'package:healthcare_app/services/queue_slot_service.dart';

// ==========================================
// 7. Active Queue Screen
// ==========================================
class ActiveQueueScreen extends StatelessWidget {
  const ActiveQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xffF5FAF6),
      body: StreamBuilder<QuerySnapshot>(
        stream: appointments.patientAppointments(user?.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
          }
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
          if (!snap.hasData || snap.data!.docs.isEmpty) return _empty('คุณยังไม่มีคิวในขณะนี้');
          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
          var latest = docs.first;
          var data = latest.data() as Map<String, dynamic>;
          if (data['status'] == QueueStatus.done) return _empty('คิวของคุณเสร็จสิ้นแล้ว');
          if (data['status'] == QueueStatus.cancelled) return _cancelled();
          String status = data['status'] ?? QueueStatus.waiting;
          bool isWait = status == QueueStatus.waiting, isCall = status == QueueStatus.called, isTreat = status == QueueStatus.treating;
          final s = statusInfo(status);
          Color statusColor = s.color;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // ===== Header =====
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                child: Row(children: [
                  Image.asset('assets/hart.png', width: 40, height: 40),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Healthcare', style: GoogleFonts.playfairDisplay(fontSize: 13, fontWeight: FontWeight.bold, color: primaryGreen)),
                    Text('Station', style: GoogleFonts.playfairDisplay(fontSize: 13, fontWeight: FontWeight.bold, color: primaryGreen)),
                  ]),
                  const Spacer(),
                  Text('คิวของฉัน', style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.bold, color: textDark)),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(children: [

                  // ===== Queue Card (same style as HomeScreen) =====
                  Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                    ),
                    child: Stack(children: [
                      Positioned(right: 0, top: 0, bottom: 0, width: 155,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.asset('assets/Log1.1.png', fit: BoxFit.cover),
                            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.white, Colors.white.withValues(alpha: 0)]))),
                          ]),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 165, 20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('คิวของคุณวันนี้', style: GoogleFonts.notoSansThai(fontSize: 14, color: textSecondary, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(data['queueNo'] ?? '-', style: GoogleFonts.prompt(fontSize: 52, fontWeight: FontWeight.bold, color: primaryGreen, height: 1.1)),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(border: Border.all(color: statusColor.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(30), color: statusColor.withValues(alpha: 0.06)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(s.icon, size: 14, color: statusColor),
                              const SizedBox(width: 6),
                              Text(s.label, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14)),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          if ((data['time'] ?? '').isNotEmpty)
                            Row(children: [Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6), Text('นัดเวลา ${data['time']}', style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14))]),
                          const SizedBox(height: 4),
                          if ((data['doctor'] ?? '').isNotEmpty)
                            Row(children: [Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6), Expanded(child: Text(data['doctor'], style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14), overflow: TextOverflow.ellipsis))]),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Cancel button
                  if (isWait)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300), foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: Text('ยกเลิกคิว', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15)),
                        onPressed: () => _confirmCancel(context, latest.id, staffUid: data['staffUid'] ?? '', date: data['date'] ?? '', time: data['time'] ?? ''),
                      ),
                    ),
                  if (isWait) const SizedBox(height: 16),

                  // ===== Progress Steps =====
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ขั้นตอนการรับบริการ', style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.bold, color: primaryGreen)),
                      const SizedBox(height: 20),
                      _step(Icons.check_circle_rounded, 'ลงทะเบียนสำเร็จ', 'บันทึกข้อมูลเรียบร้อย', true, isLast: false),
                      _step(Icons.favorite_rounded, 'รอพบนักกายภาพบำบัด', 'กรุณารอเจ้าหน้าที่เรียกคิว', isWait || isCall || isTreat, isActive: isWait, isLast: false),
                      _step(Icons.campaign_rounded, 'เรียกคิว', 'เชิญที่ห้องตรวจ', isCall || isTreat, isActive: isCall, isLast: false),
                      _step(Icons.medical_services_rounded, 'เข้ารับการรักษา', 'พบนักกายภาพบำบัดตามคิว', isTreat, isActive: isTreat, isLast: true),
                    ]),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmCancel(BuildContext context, String docId, {String staffUid = '', String date = '', String time = ''}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 10), Text('ยืนยันการยกเลิกคิว', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        content: Text('คุณต้องการยกเลิกคิวนี้ใช่หรือไม่?\nไม่สามารถนำคิวกลับคืนได้', style: TextStyle(color: textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('ไม่ยกเลิก', style: TextStyle(color: textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await appointments.cancelByPatient(docId);
                if (staffUid.isNotEmpty && date.isNotEmpty && time.isNotEmpty) {
                  queueSlots.release(staffUid: staffUid, date: date, time: time);
                }
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคิวเรียบร้อยแล้ว'), backgroundColor: Colors.red));
              } catch (e) {
                // กติกาความปลอดภัยยอมให้ยกเลิกเฉพาะคิวที่ยัง 'กำลังรอ' — ถ้าเจ้าหน้าที่เรียกคิวตัดหน้าไปแล้ว การยกเลิกจะถูกปฏิเสธ
                debugPrint('cancel appointment failed: $e');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคิวไม่สำเร็จ คิวอาจถูกเรียกไปแล้ว กรุณาลองใหม่'), backgroundColor: Colors.orange));
              }
            },
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
  }

  Widget _empty(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: lightGreen, shape: BoxShape.circle), child: const Icon(Icons.event_busy_rounded, size: 56, color: primaryGreen)),
    const SizedBox(height: 16),
    Text(msg, style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 16, fontWeight: FontWeight.w500)),
    const SizedBox(height: 8),
    Text('กดแท็บ "หน้าแรก" เพื่อจองคิว', style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14)),
  ]));

  Widget _cancelled() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.cancel_rounded, size: 60, color: Colors.red)),
    const SizedBox(height: 16),
    Text('คิวถูกยกเลิกแล้ว', style: GoogleFonts.notoSansThai(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
    const SizedBox(height: 8),
    Text('สามารถจองคิวใหม่ได้เลย', style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14)),
  ]));

  Widget _step(IconData icon, String title, String sub, bool done, {bool isActive = false, required bool isLast}) {
    Color color = isActive ? Colors.orange.shade600 : (done ? primaryGreen : Colors.grey.shade300);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: done || isActive ? LinearGradient(colors: isActive ? [Colors.orange.shade300, Colors.orange.shade700] : [const Color(0xff52b788), const Color(0xff1b4332)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            color: done || isActive ? null : Colors.grey.shade200,
            shape: BoxShape.circle,
            boxShadow: done || isActive ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 4))] : [],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        if (!isLast) Container(width: 2, height: 36, margin: const EdgeInsets.symmetric(vertical: 4), decoration: BoxDecoration(gradient: done ? const LinearGradient(colors: [Color(0xff52b788), Color(0xff1b4332)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null, color: done ? null : Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
      ]),
      const SizedBox(width: 16),
      Expanded(child: Padding(
        padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: done || isActive ? textDark : textSecondary)),
          const SizedBox(height: 3),
          Text(sub, style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14)),
        ]),
      )),
      if (done && !isActive) const Icon(Icons.check_circle_rounded, color: primaryGreen, size: 20),
    ]);
  }
}
