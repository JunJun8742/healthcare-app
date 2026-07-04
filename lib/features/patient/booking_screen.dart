import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/appointment_service.dart';
import 'package:healthcare_app/services/availability_service.dart';
import 'package:healthcare_app/services/user_service.dart';
import 'package:healthcare_app/features/patient/main_navigation.dart';

// ==========================================
// 6. Booking Screen
// ==========================================
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int selectedDateIndex = 0;
  int selectedStaffIndex = 0;
  int selectedTimeIndex = 0;
  bool isSubmitting = false;
  List<String> availableTimes = [];
  bool loadingTimes = false;
  List<Map<String, dynamic>> staffList = [];
  bool loadingStaff = false;
  String? selectedMachineId;
  String selectedMachineName = '';

  bool get _canSubmit => staffList.isNotEmpty && availableTimes.isNotEmpty && selectedMachineId != null && !loadingTimes && !loadingStaff;

  String get _missingHint {
    if (loadingStaff || loadingTimes) return 'กำลังโหลดข้อมูล...';
    if (staffList.isEmpty) return 'ยังไม่มีเจ้าหน้าที่ให้เลือก';
    if (availableTimes.isEmpty) return 'ไม่มีเวลาว่างในวันนี้ กรุณาเลือกวันอื่น';
    if (selectedMachineId == null) return 'กรุณาเลือกเครื่องที่ใช้';
    return '';
  }

  late List<DateTime> upcomingDays;
  final List<String> thaiDayNames = ['', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

  @override
  void initState() {
    super.initState();
    DateTime today = DateTime.now();
    upcomingDays = List.generate(7, (i) => today.add(Duration(days: i)));
    for (int i = 0; i < upcomingDays.length; i++) {
      if (upcomingDays[i].weekday != DateTime.saturday && upcomingDays[i].weekday != DateTime.sunday) {
        selectedDateIndex = i; break;
      }
    }
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => loadingStaff = true);
    try {
      var staffData = await users.staffUsers();
      if (mounted) setState(() { staffList = staffData; loadingStaff = false; });
    } catch (_) {
      if (mounted) setState(() => loadingStaff = false);
    }
    _loadAvailability();
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';

  Future<void> _loadAvailability() async {
    if (!mounted) return;
    setState(() => loadingTimes = true);
    String dateStr = _fmt(upcomingDays[selectedDateIndex]);
    try {
      String staffUid = staffList.isNotEmpty ? (staffList[selectedStaffIndex]['uid'] ?? '') : '';
      List<String> times = await availability.openTimes(staffUid: staffUid, date: dateStr);
      Map<String, dynamic> bookedTimesMap = await availability.bookedTimes(staffUid: staffUid, date: dateStr);
      List<String> freeTimes = times.where((t) => bookedTimesMap[t] == null || bookedTimesMap[t] == false).toList();
      if (mounted) setState(() { availableTimes = freeTimes; selectedTimeIndex = 0; loadingTimes = false; });
    } catch (_) {
      if (mounted) setState(() { availableTimes = []; loadingTimes = false; });
    }
  }

  Future<BookingOutcome> submitBooking() async {
    try {
      setState(() => isSubmitting = true);
      User? user = FirebaseAuth.instance.currentUser;
      final outcome = await appointments.createBooking(
        patientUid: user!.uid,
        doctor: staffList.isNotEmpty ? (staffList[selectedStaffIndex]['fullname'] ?? 'นักกายภาพ') : 'นักกายภาพ',
        staffUid: staffList.isNotEmpty ? (staffList[selectedStaffIndex]['uid'] ?? '') : '',
        date: _fmt(upcomingDays[selectedDateIndex]),
        time: availableTimes[selectedTimeIndex],
        machineId: selectedMachineId ?? '',
        machineName: selectedMachineName,
      );
      // Snackbar อธิบายเหตุจองไม่ได้เพราะมีคิวค้าง — sheet จะปิดตัวเฉย ๆ ไม่ซ้อน error
      if (outcome is BookingBlockedByActiveQueue && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณมีคิวที่ยังไม่เสร็จสิ้นอยู่แล้ว'), backgroundColor: Colors.orange));
      }
      return outcome;
    } catch (e) {
      return const BookingFailed();
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _showConfirmSheet() {
    final staff = staffList[selectedStaffIndex];
    final dateStr = _fmt(upcomingDays[selectedDateIndex]);
    final time = availableTimes[selectedTimeIndex];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        bool submitting = false;
        String? error;
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          Widget row(IconData ic, String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(ic, color: primaryGreen, size: 22),
              const SizedBox(width: kGapM),
              Text(label, style: tCaption()),
              const Spacer(),
              Flexible(child: Text(value, style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.end)),
            ]),
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('ยืนยันการจองคิว', style: tTitle(), textAlign: TextAlign.center),
              const SizedBox(height: kGapL),
              row(Icons.person_rounded, 'เจ้าหน้าที่', staff['fullname'] ?? 'นักกายภาพ'),
              row(Icons.calendar_month_rounded, 'วันที่', dateStr),
              row(Icons.access_time_rounded, 'เวลา', time),
              if (error != null) ...[
                const SizedBox(height: kGapM),
                Text(error!, style: tCaption(const Color(0xffB91C1C)), textAlign: TextAlign.center),
              ],
              const SizedBox(height: kGapXL),
              SizedBox(height: 56, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
                onPressed: submitting ? null : () async {
                  setSheet(() { submitting = true; error = null; });
                  final outcome = await submitBooking();
                  if (!sheetCtx.mounted) return;
                  if (outcome is BookingBlockedByActiveQueue) {
                    // Orange snackbar (shown by submitBooking) already explains
                    // this outcome — just close the sheet, no in-sheet error.
                    Navigator.pop(sheetCtx);
                  } else if (outcome is BookingSuccess) {
                    Navigator.pop(sheetCtx);
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => BookingSuccessScreen(
                        queueNo: outcome.queueNo,
                        doctor: staffList[selectedStaffIndex]['fullname'] ?? 'นักกายภาพ',
                        date: _fmt(upcomingDays[selectedDateIndex]),
                        time: availableTimes[selectedTimeIndex],
                        machineName: selectedMachineName,
                      )), (r) => false);
                    }
                  } else {
                    setSheet(() { submitting = false; error = 'จองไม่สำเร็จ ช่วงเวลานี้อาจถูกจองแล้ว กรุณาเลือกเวลาใหม่'; });
                    _loadAvailability();
                  }
                },
                child: submitting
                    ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Text('ยืนยันการจอง', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
              )),
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(sheetCtx),
                child: Text('ยกเลิก', style: tBody(textSecondary)),
              ),
            ]),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffEDF7F1),
      body: Column(children: [
        // ===== Header =====
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryGreen, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Text('จองคิวใหม่', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
            const Spacer(),
            Image.asset('assets/hart.png', width: 36, height: 36),
          ]),
        ),

        // ===== Body =====
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Step 1: วันที่ ──
            _bookingCard(
              step: 1, icon: Icons.calendar_month_rounded, title: '1. เลือกวันที่นัดหมาย',
              child: SizedBox(
                height: 82,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal, itemCount: upcomingDays.length,
                  itemBuilder: (_, i) {
                    DateTime date = upcomingDays[i];
                    bool isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
                    bool isSel = i == selectedDateIndex && !isWeekend;
                    return GestureDetector(
                      onTap: isWeekend ? null : () { setState(() => selectedDateIndex = i); _loadAvailability(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 58, margin: const EdgeInsets.only(right: 10),
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: isWeekend ? Colors.grey.shade100 : (isSel ? primaryGreen : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: isSel ? null : Border.all(color: isWeekend ? Colors.grey.shade200 : lightGreen),
                          boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : [],
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(thaiDayNames[date.weekday], style: GoogleFonts.notoSansThai(fontSize: 11, fontWeight: FontWeight.bold, color: isWeekend ? Colors.grey.shade400 : (isSel ? Colors.white70 : primaryGreen.withValues(alpha: 0.7)))),
                          const SizedBox(height: 2),
                          Text('${date.day}', style: GoogleFonts.prompt(fontSize: 22, fontWeight: FontWeight.bold, color: isWeekend ? Colors.grey.shade400 : (isSel ? Colors.white : textDark))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: kGapXL),

            // ── Step 2: นักกายภาพ ──
            _bookingCard(
              step: 2, icon: Icons.person_rounded, title: '2. เลือกนักกายภาพ',
              child: loadingStaff
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: primaryGreen)))
                : staffList.isEmpty
                  ? _infoBox('ยังไม่มีนักกายภาพในระบบ', Colors.orange)
                  : Column(children: List.generate(staffList.length, (i) {
                      bool isSel = i == selectedStaffIndex;
                      final photo = staffList[i]['photoBase64'] ?? '';
                      ImageProvider? photoImg;
                      if (photo.isNotEmpty) { try { photoImg = MemoryImage(base64Decode(photo)); } catch (_) {} }
                      return GestureDetector(
                        onTap: () { setState(() { selectedStaffIndex = i; selectedTimeIndex = 0; }); _loadAvailability(); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: isSel ? lightGreen : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSel ? primaryGreen : lightGreen, width: isSel ? 1.5 : 1),
                          ),
                          child: Row(children: [
                            Stack(children: [
                              CircleAvatar(radius: 26, backgroundColor: lightGreen, backgroundImage: photoImg, child: photoImg == null ? const Icon(Icons.person_rounded, color: primaryGreen, size: 24) : null),
                              if (isSel) Positioned(bottom: 0, right: 0, child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(color: primaryGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                child: const Icon(Icons.check, color: Colors.white, size: 9),
                              )),
                            ]),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(staffList[i]['fullname'] ?? 'นักกายภาพ', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                              Text('นักกายภาพบำบัด', style: GoogleFonts.notoSansThai(fontSize: 12, color: Colors.grey.shade500)),
                            ])),
                            if (isSel) Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: primaryGreen, borderRadius: BorderRadius.circular(20)),
                              child: Text('เลือกแล้ว', style: GoogleFonts.notoSansThai(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ]),
                        ),
                      );
                    })),
            ),
            const SizedBox(height: kGapXL),

            // ── Step 3: เครื่อง ──
            _bookingCard(
              step: 3, icon: Icons.computer_rounded, title: '3. เลือกเครื่องที่ใช้',
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('machine_status').snapshots(),
                builder: (context, machineSnap) {
                  if (!machineSnap.hasData || machineSnap.data!.docs.isEmpty) {
                    return _infoBox('ไม่พบข้อมูลเครื่อง', Colors.grey);
                  }
                  return Column(children: machineSnap.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final bool? isActive = data['is_active'] as bool?;
                    final Timestamp? lastUpd = data['last_updated'] as Timestamp?;
                    final String name = data['name'] ?? doc.id;
                    bool stale = false;
                    if (lastUpd != null) { stale = DateTime.now().difference(lastUpd.toDate()).inSeconds >= 30; }
                    else if (data.containsKey('is_active')) { stale = true; }
                    Color sColor; String sText; IconData sIcon;
                    if (stale || isActive == null) { sColor = Colors.orange; sText = 'ไม่ทราบสถานะ'; sIcon = Icons.help_outline_rounded; }
                    else if (isActive) { sColor = primaryGreen; sText = 'กำลังทำงาน'; sIcon = Icons.play_circle_rounded; }
                    else { sColor = Colors.grey; sText = 'ว่างอยู่'; sIcon = Icons.pause_circle_rounded; }
                    bool isSel = selectedMachineId == doc.id;
                    return GestureDetector(
                      onTap: () => setState(() { selectedMachineId = doc.id; selectedMachineName = name; }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: isSel ? primaryGreen : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSel ? primaryGreen : lightGreen, width: isSel ? 1.5 : 1),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: isSel ? Colors.white.withValues(alpha: 0.2) : sColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(sIcon, color: isSel ? Colors.white : sColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: isSel ? Colors.white : textDark)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: isSel ? Colors.white.withValues(alpha: 0.2) : sColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text(sText, style: GoogleFonts.notoSansThai(fontSize: 11, color: isSel ? Colors.white : sColor, fontWeight: FontWeight.w600)),
                            ),
                          ])),
                          if (isSel) Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, color: primaryGreen, size: 15),
                          ),
                        ]),
                      ),
                    );
                  }).toList());
                },
              ),
            ),
            const SizedBox(height: kGapXL),

            // ── Step 4: เวลา ──
            _bookingCard(
              step: 4, icon: Icons.access_time_rounded, title: '4. เลือกเวลา',
              child: loadingTimes
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: primaryGreen)))
                : availableTimes.isEmpty
                  ? _infoBox('ไม่มีช่วงเวลาที่เปิดในวันนี้', Colors.orange)
                  : GridView.builder(
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.7, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: availableTimes.length,
                      itemBuilder: (_, i) {
                        bool isSel = i == selectedTimeIndex;
                        String time = availableTimes[i];
                        return GestureDetector(
                          onTap: () => setState(() => selectedTimeIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            constraints: const BoxConstraints(minHeight: 48),
                            decoration: BoxDecoration(
                              color: isSel ? primaryGreen : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: isSel ? null : Border.all(color: lightGreen),
                              boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))] : [],
                            ),
                            child: Center(child: Text(time, style: GoogleFonts.prompt(fontWeight: FontWeight.bold, fontSize: 15, color: isSel ? Colors.white : textDark))),
                          ),
                        );
                      },
                    ),
            ),

          ]),
        )),

        // ===== Bottom-pinned submit button =====
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_canSubmit)
              Padding(
                padding: const EdgeInsets.only(bottom: kGapS),
                child: Text(_missingHint, style: tCaption(const Color(0xffB7791F))),
              ),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen, foregroundColor: Colors.white,
                  disabledBackgroundColor: primaryGreen.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                ),
                onPressed: _canSubmit && !isSubmitting ? _showConfirmSheet : null,
                child: isSubmitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('จองคิว', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bookingCard({required int step, required IconData icon, required String title, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text('$step', style: GoogleFonts.prompt(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: primaryGreen, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text(title, style: tTitle())),
      ]),
      const SizedBox(height: 14),
      child,
    ])),
  );


  Widget _infoBox(String msg, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Row(children: [
      Icon(Icons.info_outline_rounded, color: color, size: 20),
      const SizedBox(width: 10),
      Text(msg, style: GoogleFonts.notoSansThai(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );

}

// ==========================================
// 6.5 Booking Success Screen
// ==========================================
class BookingSuccessScreen extends StatelessWidget {
  final String queueNo, doctor, date, time, machineName;
  const BookingSuccessScreen({super.key, required this.queueNo, required this.doctor, required this.date, required this.time, required this.machineName});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData ic, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(ic, color: primaryGreen, size: 22),
        const SizedBox(width: kGapM),
        Text(label, style: tCaption()),
        const Spacer(),
        Flexible(child: Text(value, style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.end)),
      ]),
    );
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: lightGreen, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: primaryGreen, size: 60),
          ),
          const SizedBox(height: kGapL),
          Text('จองคิวสำเร็จ', style: GoogleFonts.notoSansThai(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGreen)),
          const SizedBox(height: kGapM),
          Text('หมายเลขคิวของคุณ', style: tCaption()),
          Text(queueNo, style: GoogleFonts.prompt(fontSize: 72, fontWeight: FontWeight.bold, color: primaryGreen)),
          const SizedBox(height: kGapL),
          Container(
            padding: const EdgeInsets.all(kCardPadding),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(kRadius),
              boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              row(Icons.person_rounded, 'เจ้าหน้าที่', doctor),
              row(Icons.calendar_month_rounded, 'วันที่', date),
              row(Icons.access_time_rounded, 'เวลา', time),
              if (machineName.isNotEmpty) row(Icons.precision_manufacturing_rounded, 'เครื่อง', machineName),
            ]),
          ),
          const Spacer(),
          SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 1)), (r) => false),
            child: Text('ดูคิวของฉัน', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: kGapM),
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const MainNavigation()), (r) => false),
            child: Text('กลับหน้าแรก', style: tBody(textSecondary)),
          ),
        ]),
      )),
    );
  }
}
