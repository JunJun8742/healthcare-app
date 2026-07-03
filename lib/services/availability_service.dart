import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/format.dart';

class AvailabilityService {
  AvailabilityService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  // staff_availability doc IDs use the RAW Thai Buddhist date (e.g. dd/MM/yyyy+543,
  // with '/' intact) — no sanitization, unlike queue_slots' dateKey.
  String docId({required String staffUid, required String date}) => '${staffUid}_$date';

  /// อ่านเวลาว่างของเจ้าหน้าที่จาก staff_availability — ใช้โดย BookingScreen
  /// เพื่อดึงรายการเวลาที่เจ้าหน้าที่เปิดไว้ในวันนั้น
  Future<List<String>> openTimes({required String staffUid, required String date}) async {
    var docSnap = await _db.collection('staff_availability').doc(docId(staffUid: staffUid, date: date)).get();
    List<String> times = [];
    if (docSnap.exists) {
      final raw = docSnap.data()?['times'];
      if (raw is List && raw.isNotEmpty) times = List<String>.from(raw);
    }
    return times;
  }

  // Patients cannot read other patients' appointments (see firestore.rules),
  // so booked/free status is derived from the queue_slots lock doc instead
  // of scanning appointments. A time is booked iff its value exists and is
  // not `false` (values are appointment-doc-id strings while booked).
  Future<Map<String, dynamic>> bookedTimes({required String staffUid, required String date}) async {
    String slotDocId = '${staffUid}_${queueSlotDateKey(date)}';
    var slotSnap = await _db.collection('queue_slots').doc(slotDocId).get();
    return slotSnap.data()?['bookedTimes'] ?? {};
  }

  /// อ่านเวลาว่างที่เจ้าหน้าที่บันทึกไว้เอง — ใช้โดย StaffAvailabilityScreen ตอนโหลดหน้า
  /// คืน null เมื่อยังไม่เคยบันทึก (doc ไม่มี/ฟิลด์ผิดรูป) — ต่างจาก Set ว่าง ซึ่งแปลว่า
  /// เคยบันทึกไว้แล้ว (ฝั่งจอใช้แยกสถานะ isLocked)
  Future<Set<String>?> staffTimes({required String staffUid, required String date}) async {
    var docSnap = await _db.collection('staff_availability').doc(docId(staffUid: staffUid, date: date)).get();
    if (docSnap.exists) {
      final raw = docSnap.data()?['times'];
      if (raw is List) return Set<String>.from(raw.map((e) => e.toString()));
    }
    return null;
  }

  /// บันทึกเวลาว่างของเจ้าหน้าที่ — ใช้โดย StaffAvailabilityScreen ตอนกดบันทึก
  Future<void> saveTimes({required String staffUid, required String date, required List<String> times}) async {
    await _db.collection('staff_availability').doc(docId(staffUid: staffUid, date: date)).set({
      'staffUid': staffUid,
      'date': date,
      'times': times,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
