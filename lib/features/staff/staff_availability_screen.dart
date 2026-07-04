import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/format.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/availability_service.dart';

// Staff: Availability Screen
class StaffAvailabilityScreen extends StatefulWidget {
  const StaffAvailabilityScreen({super.key});
  @override
  State<StaffAvailabilityScreen> createState() => _StaffAvailabilityScreenState();
}

class _StaffAvailabilityScreenState extends State<StaffAvailabilityScreen> {
  int selectedDateIndex = 0;
  Set<String> selectedTimes = {};
  bool isSaving = false;
  bool isLoading = false;
  bool isLocked = false;
  late List<DateTime> upcomingDays;
  final List<String> thaiDayNames = ['', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

  @override
  void initState() {
    super.initState();
    upcomingDays = List.generate(14, (i) => DateTime.now().add(Duration(days: i)));
    for (int i = 0; i < upcomingDays.length; i++) {
      if (upcomingDays[i].weekday != DateTime.saturday && upcomingDays[i].weekday != DateTime.sunday) {
        selectedDateIndex = i; break;
      }
    }
    _load();
  }

  Future<void> _load() async {
    setState(() { isLoading = true; selectedTimes = {}; isLocked = false; });
    try {
      String staffUid = FirebaseAuth.instance.currentUser?.uid ?? 'staff';
      Set<String>? times = await availability.staffTimes(staffUid: staffUid, date: thaiBuddhistDate(upcomingDays[selectedDateIndex]));
      if (times != null && mounted) setState(() { selectedTimes = times; isLocked = true; });
    } catch (_) {}
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _save() async {
    setState(() => isSaving = true);
    try {
      String dateStr = thaiBuddhistDate(upcomingDays[selectedDateIndex]);
      List<String> sorted = selectedTimes.toList()..sort((a, b) {
        final aP = a.split(':'); final bP = b.split(':');
        int aMin = int.parse(aP[0]) * 60 + int.parse(aP[1]);
        int bMin = int.parse(bP[0]) * 60 + int.parse(bP[1]);
        return aMin.compareTo(bMin);
      });
      await availability.saveTimes(staffUid: FirebaseAuth.instance.currentUser?.uid ?? '', date: dateStr, times: sorted);
      if (mounted) { setState(() => isLocked = true); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกเวลาว่างสำหรับ $dateStr แล้ว'), backgroundColor: Colors.green)); }
    } catch (e) {
      debugPrint('Save availability error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อินเทอร์เน็ตขัดข้อง กรุณาตรวจสอบการเชื่อมต่อ'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now(), builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (picked != null && mounted) {
      String t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() => selectedTimes.add(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> sortedSelected = selectedTimes.toList()..sort((a, b) {
      final aP = a.split(':'); final bP = b.split(':');
      return (int.parse(aP[0]) * 60 + int.parse(aP[1])).compareTo(int.parse(bP[0]) * 60 + int.parse(bP[1]));
    });
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(bottom: false, child: Column(children: [
        // White header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.schedule_rounded, color: primaryGreen, size: 22)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ตั้งเวลาว่าง', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                Text('เลือกวันและช่วงเวลาที่พร้อมให้บริการ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 14),
            SizedBox(height: 72, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: upcomingDays.length, itemBuilder: (_, i) {
              DateTime date = upcomingDays[i];
              bool isWe = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
              bool isSel = i == selectedDateIndex;
              return GestureDetector(
                onTap: isWe ? null : () { setState(() => selectedDateIndex = i); _load(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56, margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isSel ? primaryGreen : (isWe ? Colors.grey.shade100 : lightGreen),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(thaiDayNames[date.weekday], style: TextStyle(color: isSel ? Colors.white70 : (isWe ? Colors.grey : primaryGreen), fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(date.day.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isSel ? Colors.white : (isWe ? Colors.grey : primaryGreen))),
                    if (isWe) Text('หยุด', style: TextStyle(fontSize: 9, color: isSel ? Colors.white60 : Colors.grey.shade400)),
                  ]),
                ),
              );
            })),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('ช่วงเวลาที่เปิด', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 16, color: textDark)),
                const Spacer(),
                if (isLocked) GestureDetector(
                  onTap: () => setState(() => isLocked = false),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: lightGreen, border: Border.all(color: primaryGreen.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit_rounded, color: primaryGreen, size: 15),
                      const SizedBox(width: 5),
                      Text('แก้ไข', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    ])),
                ),
              ]),
              const SizedBox(height: 14),
              if (isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: primaryGreen)))
              else if (isLocked) ...[
                sortedSelected.isEmpty
                  ? Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.orange.shade200)),
                      child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange), const SizedBox(width: 10), Expanded(child: Text('ยังไม่มีเวลาว่างที่บันทึกไว้', style: GoogleFonts.notoSansThai(color: Colors.orange.shade800, fontWeight: FontWeight.w500)))]))
                  : Wrap(spacing: 10, runSpacing: 10, children: sortedSelected.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryGreen.withValues(alpha: 0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.access_time_rounded, color: primaryGreen, size: 15),
                        const SizedBox(width: 6),
                        Text(t, style: GoogleFonts.prompt(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                      ]),
                    )).toList()),
              ] else ...[
                if (sortedSelected.isNotEmpty) ...[
                  Wrap(spacing: 10, runSpacing: 10, children: sortedSelected.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryGreen.withValues(alpha: 0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.access_time_rounded, color: primaryGreen, size: 15),
                      const SizedBox(width: 6),
                      Text(t, style: GoogleFonts.prompt(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      GestureDetector(onTap: () => setState(() => selectedTimes.remove(t)), child: const Icon(Icons.close_rounded, size: 15, color: Colors.red)),
                    ]),
                  )).toList()),
                  const SizedBox(height: 14),
                ],
                GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: primaryGreen.withValues(alpha: 0.3), width: 1.5)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_alarm_rounded, color: primaryGreen),
                      const SizedBox(width: 8),
                      Text('+ เพิ่มช่วงเวลา', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
                  color: selectedTimes.isEmpty ? Colors.orange.shade50 : lightGreen,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selectedTimes.isEmpty ? Colors.orange.shade200 : primaryGreen.withValues(alpha: 0.2)),
                ), child: Row(children: [
                  Icon(selectedTimes.isEmpty ? Icons.warning_amber_rounded : Icons.check_circle_rounded, color: selectedTimes.isEmpty ? Colors.orange : primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(child: Text(selectedTimes.isEmpty ? 'ยังไม่ได้เลือกช่วงเวลา' : 'เลือกแล้ว ${selectedTimes.length} ช่วงเวลา', style: GoogleFonts.notoSansThai(color: selectedTimes.isEmpty ? Colors.orange.shade800 : primaryGreen, fontWeight: FontWeight.w500))),
                ])),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: isSaving ? null : _save,
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: isSaving ? Colors.grey.shade200 : primaryGreen,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSaving ? [] : [BoxShadow(color: primaryGreen.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Center(child: isSaving
                      ? const CircularProgressIndicator(color: primaryGreen)
                      : Text('บันทึกเวลาว่าง', style: GoogleFonts.notoSansThai(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ])),
    );
  }
}
