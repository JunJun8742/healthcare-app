import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/format.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/appointment_service.dart';

// Staff: Treatment History — เลือกวันได้
class StaffTreatmentHistoryScreen extends StatefulWidget {
  const StaffTreatmentHistoryScreen({super.key});
  @override
  State<StaffTreatmentHistoryScreen> createState() => _StaffTreatmentHistoryScreenState();
}

class _StaffTreatmentHistoryScreenState extends State<StaffTreatmentHistoryScreen> {
  DateTime? selectedDate;

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    String? filterDate = selectedDate != null ? thaiBuddhistDate(selectedDate!) : null;
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(bottom: false, child: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.history_rounded, color: primaryGreen, size: 22)),
              const SizedBox(width: 12),
              Text('ประวัติการรักษา', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: selectedDate != null ? primaryGreen.withValues(alpha: 0.4) : Colors.transparent)),
                    child: Row(children: [
                      const Icon(Icons.calendar_month_rounded, color: primaryGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(selectedDate != null ? 'วันที่: $filterDate' : 'เลือกวันที่เพื่อกรอง', style: GoogleFonts.notoSansThai(color: selectedDate != null ? primaryGreen : Colors.grey.shade600, fontWeight: FontWeight.w500, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              if (selectedDate != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => selectedDate = null),
                  child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.close_rounded, color: Colors.red, size: 18)),
                ),
              ],
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: appointments.allAppointments(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xff00897b)));
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history_rounded, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('ยังไม่มีประวัติ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 16)),
                ]));
              }
              var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
              if (filterDate != null) docs = docs.where((d) => (d.data() as Map)['date'] == filterDate).toList();
              if (docs.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.search_off_rounded, size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('ไม่พบประวัติวันที่ $filterDate', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 15)),
                ]));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  var data = docs[i].data() as Map<String, dynamic>;
                  String status = data['status'] ?? QueueStatus.waiting;
                  Color sc; IconData sIcon;
                  switch (status) {
                    case QueueStatus.done: sc = const Color(0xff2e7d32); sIcon = Icons.check_circle_rounded; break;
                    case QueueStatus.treating: sc = const Color(0xffe65100); sIcon = Icons.medical_services_rounded; break;
                    case QueueStatus.called: sc = const Color(0xff1565c0); sIcon = Icons.campaign_rounded; break;
                    case QueueStatus.cancelled: sc = Colors.red.shade700; sIcon = Icons.cancel_rounded; break;
                    default: sc = const Color(0xff2d6a4f); sIcon = Icons.access_time_rounded;
                  }
                  String notes = (data['notes'] ?? '').toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: sc.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)), BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5)],
                    ),
                    child: Padding(padding: const EdgeInsets.all(15), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [sc.withValues(alpha: 0.7), sc], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: sc.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                      ), child: Icon(sIcon, color: Colors.white, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('คิว ${data['queueNo'] ?? '-'}', style: GoogleFonts.prompt(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                          const Spacer(),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: Text(status, style: GoogleFonts.notoSansThai(color: sc, fontWeight: FontWeight.bold, fontSize: 11))),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade400), const SizedBox(width: 5), Text(data['patientName'] ?? '-', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, fontSize: 13, color: textDark))]),
                        const SizedBox(height: 3),
                        Row(children: [Icon(Icons.local_hospital_outlined, size: 14, color: Colors.grey.shade400), const SizedBox(width: 5), Expanded(child: Text(data['doctor'] ?? '-', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)))]),
                        const SizedBox(height: 3),
                        Row(children: [Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade400), const SizedBox(width: 5), Text('${data['date'] ?? ''}  ${data['time'] ?? ''}', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 12))]),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(10)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.note_alt_outlined, size: 14, color: primaryGreen), const SizedBox(width: 6), Expanded(child: Text(notes, style: GoogleFonts.notoSansThai(fontSize: 12, color: primaryGreen)))])),
                        ],
                      ])),
                    ])),
                  );
                },
              );
            },
          ),
        ),
      ])),
    );
  }
}
