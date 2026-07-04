import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/appointment_service.dart';
import 'package:healthcare_app/services/queue_slot_service.dart';
import 'package:healthcare_app/services/notification_service.dart';
import 'package:healthcare_app/features/patient/notification_screen.dart';

// Staff: Queue Management + MachineStatusCard
class StaffQueueScreen extends StatefulWidget {
  const StaffQueueScreen({super.key});
  @override
  State<StaffQueueScreen> createState() => _StaffQueueScreenState();
}

class _StaffQueueScreenState extends State<StaffQueueScreen> {
  DateTime selectedDay = DateTime.now();
  String searchQuery = '';
  String statusFilter = ''; // '' = ทั้งหมด
  bool _isCustomDay = false;
  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';
  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dayChip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, color: selected ? Colors.white : textDark)),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: primaryGreen,
    backgroundColor: Colors.grey.shade100,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
  );

  Widget _statusChip(String status) {
    final selected = statusFilter == status;
    final info = status.isEmpty ? null : statusInfo(status);
    final label = status.isEmpty ? 'ทั้งหมด' : info!.label;
    final color = status.isEmpty ? primaryGreen : info!.color;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, fontSize: 13, color: selected ? Colors.white : color)),
      selected: selected,
      onSelected: (_) => setState(() => statusFilter = status),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: color.withValues(alpha: 0.3))),
    );
  }

  // [staffUid]/[date]/[time] identify the appointment's queue_slots lock so a
  // cancel can release it (and an undo can re-lock it). [prevValues] carries
  // the PRIOR value of any key in [extra] (e.g. an existing 'notes') so undo
  // restores it instead of wiping it with FieldValue.delete().
  Future<void> _changeStatus(BuildContext context, String docId, String queueNo, String patientName, String fromStatus, String toStatus,
      {Map<String, dynamic> extra = const {}, Map<String, dynamic> prevValues = const {}, String staffUid = '', String date = '', String time = ''}) async {
    final s = statusInfo(toStatus);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('ยืนยันเปลี่ยนสถานะ', style: tTitle()),
        content: Text('เปลี่ยนคิว $queueNo — $patientName\nเป็น "${s.label}" ใช่หรือไม่?', style: tBody()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text('ไม่ใช่', style: tBody(textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: s.color, foregroundColor: Colors.white, minimumSize: const Size(100, 48)),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await appointments.updateStatus(docId, toStatus: toStatus, extra: extra);
    if (toStatus == 'ยกเลิก' && staffUid.isNotEmpty && date.isNotEmpty && time.isNotEmpty) {
      queueSlots.release(staffUid: staffUid, date: date, time: time);
    }
    if (!context.mounted) return;
    final undoable = toStatus == 'ยกเลิก' || toStatus == 'เสร็จสิ้น';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('เปลี่ยนสถานะคิว $queueNo เป็น ${s.label} แล้ว', style: GoogleFonts.notoSansThai()),
      backgroundColor: s.color,
      duration: const Duration(seconds: 5),
      action: undoable
          ? SnackBarAction(label: 'เลิกทำ', textColor: Colors.white, onPressed: () async {
              // Guard: only revert if the doc's status is still what we just
              // set it to — otherwise a concurrent status change happened and
              // undo must not clobber it.
              final cur = await appointments.getAppointment(docId);
              if (!cur.exists || cur.data()?['status'] != toStatus) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('ไม่สามารถเลิกทำได้ สถานะถูกเปลี่ยนไปแล้ว', style: GoogleFonts.notoSansThai()),
                    backgroundColor: Colors.orange,
                  ));
                }
                return;
              }
              final revertMap = {'status': fromStatus, 'updatedAt': FieldValue.serverTimestamp()};
              for (final k in extra.keys) {
                revertMap[k] = prevValues.containsKey(k) ? prevValues[k] : FieldValue.delete();
              }
              await appointments.updateFields(docId, revertMap);
              if (toStatus == 'ยกเลิก' && staffUid.isNotEmpty && date.isNotEmpty && time.isNotEmpty) {
                queueSlots.relock(staffUid: staffUid, date: date, time: time, apptId: docId);
              }
            })
          : null,
    ));
  }

  Future<void> _callNext(BuildContext context, List<QueryDocumentSnapshot> docs) async {
    final waiting = docs.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'กำลังรอ').toList()
      ..sort((a, b) => ((a.data() as Map<String, dynamic>)['queueNo'] ?? '').toString()
          .compareTo(((b.data() as Map<String, dynamic>)['queueNo'] ?? '').toString()));
    if (waiting.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ไม่มีคิวที่กำลังรอในวันนี้', style: GoogleFonts.notoSansThai()), backgroundColor: Colors.orange));
      return;
    }
    final m = waiting.first.data() as Map<String, dynamic>;
    await _changeStatus(context, waiting.first.id, m['queueNo'] ?? '', m['patientName'] ?? '', 'กำลังรอ', 'เรียกคิว');
  }

  void _completeDialog(BuildContext ctx, String docId, String queueNo, String patientName, {String prevNotes = '', String staffUid = '', String date = '', String time = ''}) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('บันทึกผลการรักษา', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('บันทึกเพิ่มเติม (ไม่บังคับ):', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, maxLines: 3, decoration: InputDecoration(hintText: 'เช่น ให้ยา / คำแนะนำ / นัดหมายครั้งถัดไป...', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              final notes = notesCtrl.text.trim();
              _changeStatus(ctx, docId, queueNo, patientName, 'กำลังรักษา', 'เสร็จสิ้น',
                  extra: {'completedAt': FieldValue.serverTimestamp(), if (notes.isNotEmpty) 'notes': notes},
                  prevValues: {if (notes.isNotEmpty && prevNotes.isNotEmpty) 'notes': prevNotes},
                  staffUid: staffUid, date: date, time: time);
            },
            child: const Text('ยืนยันเสร็จสิ้น'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<QuerySnapshot>(
        stream: appointments.appointmentsForDate(_fmtDate(selectedDay)),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
          // allDocs: non-terminal (excludes เสร็จสิ้น/ยกเลิก) — drives header stats
          // and _callNext, which must never consider completed/cancelled queues.
          var allDocs = (snap.data?.docs ?? []).where((d) => !['เสร็จสิ้น', 'ยกเลิก'].contains(d['status'])).toList()
            ..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return ta.compareTo(tb); });
          // fullDayDocs: every appointment for the day, terminal states included —
          // needed so the 'เสร็จสิ้น' chip has something to show.
          var fullDayDocs = (snap.data?.docs ?? []).toList()
            ..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return ta.compareTo(tb); });
          var listSource = statusFilter == 'เสร็จสิ้น' ? fullDayDocs : allDocs;
          var docs = listSource.where((d) {
            final m = d.data() as Map<String, dynamic>;
            final okStatus = statusFilter.isEmpty || m['status'] == statusFilter;
            final q = searchQuery.toLowerCase();
            final okSearch = q.isEmpty ||
                (m['patientName'] ?? '').toString().toLowerCase().contains(q) ||
                (m['queueNo'] ?? '').toString().contains(q);
            return okStatus && okSearch;
          }).toList();
          int waiting = allDocs.where((d) => d['status'] == 'กำลังรอ').length;
          int calling = allDocs.where((d) => d['status'] == 'เรียกคิว').length;
          int treating = allDocs.where((d) => d['status'] == 'กำลังรักษา').length;

          return Column(children: [
            // ── Header ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Image.asset('assets/hart.png', width: 36),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('จัดการคิวผู้ป่วย', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                    Text('ติดตามสถานะแบบเรียลไทม์', style: GoogleFonts.notoSansThai(fontSize: 11, color: Colors.grey.shade400)),
                  ]),
                  const Spacer(),
                  Stack(clipBehavior: Clip.none, children: [
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.notifications_rounded, color: primaryGreen, size: 20),
                      ),
                    ),
                    Positioned(
                      top: -2, right: -2,
                      child: StreamBuilder<QuerySnapshot>(
                        stream: notifications.unreadProbe(FirebaseAuth.instance.currentUser?.uid),
                        builder: (context, unreadSnap) {
                          final hasUnread = unreadSnap.data?.docs.isNotEmpty ?? false;
                          if (!hasUnread) return const SizedBox.shrink();
                          return Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                          );
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Text('${allDocs.length} คิว', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  _qStatBlock('กำลังรอ', waiting, primaryGreen, Icons.access_time_rounded),
                  const SizedBox(width: 10),
                  _qStatBlock('เรียกแล้ว', calling, Colors.blue.shade600, Icons.campaign_rounded),
                  const SizedBox(width: 10),
                  _qStatBlock('กำลังรักษา', treating, Colors.orange.shade700, Icons.medical_services_rounded),
                ]),
              ]),
            ),
            const Divider(height: 1),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 48,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    _dayChip('วันนี้', _isSameDay(selectedDay, DateTime.now()) && !_isCustomDay, () {
                      setState(() { selectedDay = DateTime.now(); _isCustomDay = false; });
                    }),
                    const SizedBox(width: kGapS),
                    _dayChip('พรุ่งนี้', _isSameDay(selectedDay, DateTime.now().add(const Duration(days: 1))) && !_isCustomDay, () {
                      setState(() { selectedDay = DateTime.now().add(const Duration(days: 1)); _isCustomDay = false; });
                    }),
                    const SizedBox(width: kGapS),
                    _dayChip(_isCustomDay ? _fmtDate(selectedDay) : 'เลือกวัน', _isCustomDay, () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDay,
                        firstDate: now.subtract(const Duration(days: 30)),
                        lastDate: now.add(const Duration(days: 30)),
                        locale: const Locale('th'),
                      );
                      if (picked != null) setState(() { selectedDay = picked; _isCustomDay = true; });
                    }),
                  ]),
                ),
                const SizedBox(height: kGapM),
                TextField(
                  onChanged: (v) => setState(() => searchQuery = v.trim()),
                  style: tBody(),
                  decoration: InputDecoration(
                    hintText: 'ค้นหาชื่อผู้ป่วยหรือเลขคิว',
                    hintStyle: tCaption(),
                    prefixIcon: const Icon(Icons.search_rounded, color: primaryGreen),
                    filled: true, fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: const BorderSide(color: primaryGreen)),
                  ),
                ),
                const SizedBox(height: kGapM),
                SizedBox(
                  height: 40,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final s in const ['', 'กำลังรอ', 'เรียกคิว', 'กำลังรักษา', 'เสร็จสิ้น'])
                      Padding(
                        padding: const EdgeInsets.only(right: kGapS),
                        child: _statusChip(s),
                      ),
                  ]),
                ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _callNext(context, allDocs),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                  ),
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text('เรียกคิวถัดไป', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ),
            Expanded(
              child: docs.isEmpty
                ? const StateMessage(icon: Icons.inbox_rounded, message: 'ไม่พบคิวตามเงื่อนไขที่เลือก')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      var doc = docs[i]; var data = doc.data() as Map<String, dynamic>;
                      String status = data['status'] ?? 'กำลังรอ';
                      String queueNo = data['queueNo'] ?? '-';
                      String patientName = data['patientName'] ?? '-';
                      Color statusColor; IconData sIcon; List<Color> btnGrad; String btnLabel; VoidCallback? btnAction;
                      switch (status) {
                        case 'เรียกคิว':
                          statusColor = Colors.blue.shade600; sIcon = Icons.campaign_rounded;
                          btnGrad = [Colors.blue.shade400, Colors.blue.shade700]; btnLabel = 'เริ่มรักษา';
                          btnAction = () => _changeStatus(context, doc.id, queueNo, patientName, 'เรียกคิว', 'กำลังรักษา');
                          break;
                        case 'กำลังรักษา':
                          statusColor = Colors.orange.shade700; sIcon = Icons.medical_services_rounded;
                          btnGrad = [Colors.green.shade400, const Color(0xff186B44)]; btnLabel = 'เสร็จสิ้น';
                          btnAction = () => _completeDialog(context, doc.id, queueNo, patientName, prevNotes: data['notes'] ?? '');
                          break;
                        case 'เสร็จสิ้น':
                          statusColor = const Color(0xff4B6358); sIcon = Icons.check_circle_rounded;
                          btnGrad = [Colors.grey.shade400, Colors.grey.shade600]; btnLabel = 'เสร็จสิ้นแล้ว';
                          btnAction = null;
                          break;
                        default:
                          statusColor = primaryGreen; sIcon = Icons.access_time_rounded;
                          btnGrad = [Colors.blue.shade300, Colors.blue.shade700]; btnLabel = 'เรียกคิว';
                          btnAction = () => _changeStatus(context, doc.id, queueNo, patientName, 'กำลังรอ', 'เรียกคิว');
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(color: statusColor.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 5)),
                            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              // Accent bar
                              Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [statusColor.withValues(alpha: 0.6), statusColor], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                                ),
                              ),
                              // Card body
                              Expanded(child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  // Top row: queue no + status + time
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(
                                      padding: const EdgeInsets.all(9),
                                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
                                      child: Icon(sIcon, color: statusColor, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('คิว ${data['queueNo'] ?? '-'}', style: GoogleFonts.prompt(fontSize: 24, fontWeight: FontWeight.bold, color: textDark, height: 1.1)),
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                                        child: Text(status, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                    ])),
                                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: [statusColor.withValues(alpha: 0.7), statusColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(data['time'] ?? '-', style: GoogleFonts.prompt(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(data['date'] ?? '', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 11)),
                                    ]),
                                  ]),
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, thickness: 0.5),
                                  const SizedBox(height: 10),
                                  // Patient info
                                  Row(children: [
                                    CircleAvatar(radius: 16, backgroundColor: lightGreen, child: Text((data['patientName'] ?? '?').toString().characters.first, style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 13))),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(data['patientName'] ?? '-', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w700, color: textDark)),
                                      Text(data['doctor'] ?? '-', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)),
                                    ])),
                                  ]),
                                  const SizedBox(height: 12),
                                  // Action button full-width
                                  GestureDetector(
                                    onTap: btnAction,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [BoxShadow(color: btnGrad.last.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                                      ),
                                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Icon(sIcon, color: Colors.white, size: 17),
                                        const SizedBox(width: 8),
                                        Text(btnLabel, style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              )),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ]);
        },
      ),
      ),
    );
  }

  Widget _qStatBlock(String label, int count, Color color, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count', style: GoogleFonts.prompt(color: color, fontWeight: FontWeight.bold, fontSize: 18, height: 1.1)),
          Text(label, style: GoogleFonts.notoSansThai(color: color.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
      ]),
    ),
  );
}
