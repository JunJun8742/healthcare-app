import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/sos_service.dart';

// Staff: SOS Screen
class StaffSOSScreen extends StatefulWidget {
  const StaffSOSScreen({super.key});
  @override
  State<StaffSOSScreen> createState() => _StaffSOSScreenState();
}

class _StaffSOSScreenState extends State<StaffSOSScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> resolve(String docId) async => sos.resolveAlert(docId);

  Future<void> _confirmResolve(BuildContext context, String docId, String patientName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('ยืนยันรับเรื่อง SOS', style: tTitle()),
        content: Text('รับเรื่องแจ้งเหตุฉุกเฉินของ $patientName ใช่หรือไม่?', style: tBody()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text('ไม่ใช่', style: tBody(textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffB91C1C), foregroundColor: Colors.white, minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await resolve(docId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('รับเรื่อง SOS ของ $patientName แล้ว', style: GoogleFonts.notoSansThai()),
      backgroundColor: primaryGreen,
    ));
  }

  Widget _sosIcon3D(IconData icon, List<Color> colors, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(color: colors.last.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 4)),
          BoxShadow(color: colors.last.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xff7F0000), Color(0xffC62828), Color(0xffEF5350)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('แจ้งเหตุฉุกเฉิน SOS', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('ระบบติดตามเหตุฉุกเฉินแบบเรียลไทม์', style: GoogleFonts.notoSansThai(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                  child: Row(children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('LIVE', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            TabBar(
              controller: _tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.notoSansThai(fontSize: 13),
              tabs: const [Tab(text: 'รอรับเรื่อง'), Tab(text: 'ประวัติ SOS')],
            ),
          ])),
        ),
        Expanded(child: TabBarView(controller: _tab, children: [_pending(), _history()])),
      ]),
    );
  }

  Widget _pending() => StreamBuilder<QuerySnapshot>(
    stream: sos.pendingAlerts(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.red));
      if (!snap.hasData || snap.data!.docs.isEmpty) return const StateMessage(icon: Icons.verified_user_rounded, message: 'ไม่มีเหตุฉุกเฉินในขณะนี้');
      var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
      return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), itemCount: docs.length, itemBuilder: (_, i) {
        var doc = docs[i]; var data = doc.data() as Map<String, dynamic>;
        DateTime dt = (data['createdAt'] as Timestamp).toDate();
        String timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xffFEF2F2),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xffB91C1C), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.red.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 6)),
              BoxShadow(color: Colors.red.withValues(alpha: 0.07), blurRadius: 40, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.red.shade700, Colors.red.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('มีผู้ขอความช่วยเหลือ!', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  Text('เวลา $timeStr น.', style: GoogleFonts.notoSansThai(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.5))),
                  child: Text('⚠ ด่วน!', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ]),
            ),
            Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _sosIcon3D(Icons.sos_rounded, [Colors.red.shade300, Colors.red.shade700], 48),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data['patientName'] ?? 'ไม่ระบุ', style: tTitle()),
                  const SizedBox(height: 3),
                  Text('อาการ: ${data['issue'] ?? '-'}', style: GoogleFonts.notoSansThai(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                ])),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffB91C1C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () => _confirmResolve(context, doc.id, data['patientName'] ?? 'ไม่ระบุ'),
                  child: Text('รับเรื่องแล้ว', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ])),
          ]),
        );
      });
    },
  );

  Widget _history() => StreamBuilder<QuerySnapshot>(
    stream: sos.resolvedAlerts(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
      if (!snap.hasData || snap.data!.docs.isEmpty) {
        return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history_toggle_off_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text('ยังไม่มีประวัติ SOS', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 16)),
        ]));
      }
      var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
      return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), itemCount: docs.length, itemBuilder: (_, i) {
        var data = docs[i].data() as Map<String, dynamic>;
        DateTime dt = (data['createdAt'] as Timestamp).toDate();
        String dateStr = '${dt.day}/${dt.month}/${dt.year + 543}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.';
        return Container(margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 3))]),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.check_circle_rounded, color: primaryGreen, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['issue'] ?? '-', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
              const SizedBox(height: 3),
              Text(data['patientName'] ?? '-', style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 12)),
              Text(dateStr, style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 11)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(10)),
              child: Text('รับเรื่องแล้ว', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 11))),
          ])),
        );
      });
    },
  );
}
