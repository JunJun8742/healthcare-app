import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/appointment_service.dart';
import 'package:healthcare_app/services/queue_slot_service.dart';
import 'package:healthcare_app/services/user_service.dart';
import 'package:healthcare_app/services/notification_service.dart';
import 'package:healthcare_app/features/patient/booking_screen.dart';
import 'package:healthcare_app/features/patient/sos_screen.dart';
import 'package:healthcare_app/features/patient/notification_screen.dart';
import 'package:healthcare_app/features/patient/history_screen.dart';

// ==========================================
// 5. Home Screen (Patient) + MachineStatusCard
// ==========================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xffF5FAF6),
      body: FutureBuilder<DocumentSnapshot>(
        future: users.getUser(user?.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
          }
          String name = 'ผู้ใช้งาน';
          String photoBase64 = '';
          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data() as Map<String, dynamic>;
            name = d['fullname'] ?? 'ผู้ใช้งาน';
            photoBase64 = d['photoBase64'] ?? '';
          }
          ImageProvider? photo;
          if (photoBase64.isNotEmpty) { try { photo = MemoryImage(base64Decode(photoBase64)); } catch (_) {} }

          return SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // ===== Header =====
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(children: [
                    // Logo
                    Row(children: [
                      Image.asset('assets/hart.png', width: 44, height: 44),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Healthcare', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold, color: primaryGreen)),
                        Text('Station', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold, color: primaryGreen)),
                      ]),
                    ]),
                    const Spacer(),
                    // Greeting
                    Row(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('สวัสดี, ${name.split(' ').first}', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w600, color: textDark)),
                        Text('จองคิวกายภาพบำบัด', style: tCaption()),
                      ]),
                      const SizedBox(width: 6),
                      const Text('👋', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      CircleAvatar(
                        radius: 18, backgroundColor: lightGreen,
                        backgroundImage: photo,
                        child: photo == null ? const Icon(Icons.person, color: primaryGreen, size: 20) : null,
                      ),
                    ]),
                  ]),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ===== Queue Card =====
                    StreamBuilder<QuerySnapshot>(
                      stream: appointments.patientAppointments(user?.uid),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
                        }
                        String qNo = ''; String status = ''; String? activeDocId;
                        String time = ''; String activeStaffUid = ''; String activeDate = '';
                        if (snap.hasData && snap.data!.docs.isNotEmpty) {
                          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
                          var latest = docs.first;
                          if (!['เสร็จสิ้น', 'ยกเลิก'].contains(latest['status'])) {
                            qNo = latest['queueNo'] ?? '';
                            status = latest['status'] ?? '';
                            activeDocId = latest.id;
                            time = latest['time'] ?? '';
                            activeStaffUid = latest['staffUid'] ?? '';
                            activeDate = latest['date'] ?? '';
                          }
                        }
                        final bool hasQueue = qNo.isNotEmpty;
                        final s = statusInfo(status);
                        Color statusColor = s.color;

                        return Container(
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: hasQueue
                            ? Stack(children: [
                                // Hospital image right side
                                Positioned(right: 0, top: 0, bottom: 0, width: 160,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                                    child: Stack(fit: StackFit.expand, children: [
                                      Image.asset('assets/Log1.1.png', fit: BoxFit.cover),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.white, Colors.white.withValues(alpha: 0)]),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                                // Content left side
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 20, 170, 20),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('คิวของคุณวันนี้', style: GoogleFonts.notoSansThai(fontSize: 14, color: textSecondary, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(qNo, style: GoogleFonts.prompt(fontSize: 52, fontWeight: FontWeight.bold, color: primaryGreen, height: 1.1)),
                                    const SizedBox(height: 12),
                                    // Status pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                        borderRadius: BorderRadius.circular(30),
                                        color: statusColor.withValues(alpha: 0.06),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(s.icon, size: 14, color: statusColor),
                                        const SizedBox(width: 6),
                                        Text(s.label, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ]),
                                    ),
                                    const SizedBox(height: 12),
                                    if (time.isNotEmpty)
                                      Row(children: [
                                        Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                                        const SizedBox(width: 6),
                                        Text('นัดเวลา $time', style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14)),
                                      ]),
                                    if (activeDocId != null && status == 'กำลังรอ') ...[
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: () => _confirmCancel(context, activeDocId!, staffUid: activeStaffUid, date: activeDate, time: time),
                                        child: Text('ยกเลิกคิว', style: GoogleFonts.notoSansThai(color: Colors.red.shade400, fontSize: 14, decoration: TextDecoration.underline)),
                                      ),
                                    ],
                                  ]),
                                ),
                              ])
                            : Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(children: [
                                  Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.calendar_month_rounded, color: primaryGreen, size: 28)),
                                  const SizedBox(width: 16),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('ยังไม่มีคิว — กดปุ่มด้านล่างเพื่อจองคิวแรกของคุณ', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
                                  ])),
                                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textSecondary),
                                ]),
                              ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // ===== Action Cards =====
                    Row(children: [
                      Expanded(child: _actionCard(context, Icons.calendar_month_rounded, 'จองคิวใหม่', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingScreen())))),
                      const SizedBox(width: 14),
                      Expanded(child: _actionCard(context, Icons.format_list_bulleted_rounded, 'ประวัติการรักษา', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())))),
                    ]),
                    const SizedBox(height: 22),

                    // ===== Services =====
                    Text('บริการของเรา', style: GoogleFonts.notoSansThai(fontSize: 15, fontWeight: FontWeight.bold, color: primaryGreen)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _serviceCard(context, 'กายภาพบำบัด', Icons.accessibility_new_rounded, false, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingScreen())))),
                      const SizedBox(width: 12),
                      Expanded(child: Stack(clipBehavior: Clip.none, children: [
                        _serviceCard(context, 'แจ้งเตือน', Icons.notifications_rounded, false, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen()))),
                        Positioned(
                          top: 8, right: 8,
                          child: StreamBuilder<QuerySnapshot>(
                            stream: notifications.unreadProbe(user?.uid),
                            builder: (context, unreadSnap) {
                              final hasUnread = unreadSnap.data?.docs.isNotEmpty ?? false;
                              if (!hasUnread) return const SizedBox.shrink();
                              return Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                              );
                            },
                          ),
                        ),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: _serviceCard(context, 'แจ้งเหตุฉุกเฉิน', Icons.sos_rounded, true, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SOSScreen())))),
                    ]),
                    const SizedBox(height: 20),
                  ]),
                ),
              ],
            ),
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

  Widget _actionCard(BuildContext ctx, IconData icon, String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: primaryGreen.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
            const BoxShadow(color: Colors.white, blurRadius: 0, offset: Offset(0, 0)),
          ],
        ),
        child: Column(children: [
          icon3D(icon, [const Color(0xff1b4332), const Color(0xff52b788)], 60),
          const SizedBox(height: 14),
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, color: textDark, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xff1b4332), Color(0xff52b788)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
          ),
        ]),
      ),
    );
  }

  Widget _serviceCard(BuildContext ctx, String title, IconData icon, bool isSOS, VoidCallback onTap) {
    final List<Color> iconColors = isSOS
        ? [Colors.red.shade300, Colors.red.shade700]
        : [const Color(0xff52b788), const Color(0xff186B44)];
    final List<Color> arrowColors = isSOS
        ? [Colors.red.shade400, Colors.red.shade700]
        : [const Color(0xff52b788), const Color(0xff1b4332)];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Column(children: [
          icon3D(icon, iconColors, 58),
          const SizedBox(height: 10),
          // 13px is the single allowed exception to the 14px minimum: 3-column layout, label duplicated by icon above.
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, fontSize: 13, color: textDark), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: arrowColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [BoxShadow(color: arrowColors[1].withValues(alpha: 0.4), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white),
          ),
        ]),
      ),
    );
  }

}
