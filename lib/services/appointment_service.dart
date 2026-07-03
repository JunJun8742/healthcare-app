import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/format.dart';

/// ผลลัพธ์การจองคิว — แทน sentinel string เดิม (__ACTIVE_QUEUE__)
/// ฝั่งจอเป็นคนแสดง snackbar/นำทางตามผลลัพธ์เอง
sealed class BookingOutcome {
  const BookingOutcome();
}

class BookingSuccess extends BookingOutcome {
  const BookingSuccess(this.queueNo);
  final String queueNo;
}

/// ผู้ป่วยมีคิวค้าง (กำลังรอ/เรียกคิว/กำลังรักษา) อยู่แล้ว
class BookingBlockedByActiveQueue extends BookingOutcome {
  const BookingBlockedByActiveQueue();
}

class BookingFailed extends BookingOutcome {
  const BookingFailed();
}

class AppointmentService {
  AppointmentService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  // ---- streams: จัดเรียง/กรองฝั่ง client เสมอ เพื่อเลี่ยง composite index ----

  Stream<QuerySnapshot<Map<String, dynamic>>> patientAppointments(String? patientUid) =>
      _db.collection('appointments').where('patientUid', isEqualTo: patientUid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> appointmentsForDate(String date) =>
      _db.collection('appointments').where('date', isEqualTo: date).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> allAppointments() =>
      _db.collection('appointments').snapshots();

  // ---- writes ----

  Future<void> cancelByPatient(String docId) =>
      _db.collection('appointments').doc(docId).update({'status': 'ยกเลิก', 'cancelledAt': FieldValue.serverTimestamp(), 'cancelledBy': 'patient'});

  Future<void> updateStatus(String docId, {required String toStatus, Map<String, dynamic> extra = const {}}) =>
      _db.collection('appointments').doc(docId).update({'status': toStatus, 'updatedAt': FieldValue.serverTimestamp(), ...extra});

  /// อ่าน doc สด ๆ ก่อน undo — กัน clobber เมื่อสถานะถูกเปลี่ยนซ้อนไปแล้ว
  Future<DocumentSnapshot<Map<String, dynamic>>> getAppointment(String docId) =>
      _db.collection('appointments').doc(docId).get();

  Future<void> updateFields(String docId, Map<String, dynamic> fields) =>
      _db.collection('appointments').doc(docId).update(fields);

  /// คิวค้างของผู้ป่วย = สถานะใดสถานะหนึ่งใน กำลังรอ/เรียกคิว/กำลังรักษา
  Future<bool> hasActiveAppointment(String patientUid) async {
    var existing = await _db.collection('appointments').where('patientUid', isEqualTo: patientUid).where('status', whereIn: ['กำลังรอ', 'เรียกคิว', 'กำลังรักษา']).get();
    return existing.docs.isNotEmpty;
  }

  /// จองคิวใน transaction เดียว: ตัดเลขคิวจาก queue_days (นับต่อวัน ทุกเจ้าหน้าที่รวมกัน)
  /// + ล็อกช่วงเวลาใน queue_slots (ต่อเจ้าหน้าที่) + สร้าง appointment
  Future<BookingOutcome> createBooking({
    required String patientUid,
    required String doctor,
    required String staffUid,
    required String date,
    required String time,
    required String machineId,
    required String machineName,
  }) async {
    try {
      if (await hasActiveAppointment(patientUid)) return const BookingBlockedByActiveQueue();

      var userDoc = await _db.collection('users').doc(patientUid).get();
      String patientName = userDoc.data()?['fullname'] ?? 'ผู้ป่วยไม่ทราบชื่อ';
      // '/' is illegal in a Firestore document-ID path segment (date is
      // Thai Buddhist dd/MM/yyyy); sanitize consistently for both doc IDs.
      String dateKey = queueSlotDateKey(date);
      // queueNo is a single shared queue board across all staff (StaffQueueScreen),
      // so the counter must be keyed per-day only, not per-staff.
      DocumentReference<Map<String, dynamic>> dayCounterRef =
          _db.collection('queue_days').doc(dateKey);
      // Slot lock stays per-staff so two different staff can share a time slot.
      DocumentReference<Map<String, dynamic>> slotRef =
          _db.collection('queue_slots').doc('${staffUid}_$dateKey');
      DocumentReference<Map<String, dynamic>> apptRef =
          _db.collection('appointments').doc();

      String? assignedQueueNo;
      await _db.runTransaction((transaction) async {
        DocumentSnapshot<Map<String, dynamic>> daySnap = await transaction.get(dayCounterRef);
        DocumentSnapshot<Map<String, dynamic>> slotSnap = await transaction.get(slotRef);
        Map<String, dynamic>? dayData = daySnap.data();
        Map<String, dynamic>? slotData = slotSnap.data();
        Map<String, dynamic> bookedTimes = Map<String, dynamic>.from(slotData?['bookedTimes'] ?? {});
        if (bookedTimes[time] != null && bookedTimes[time] != false) {
          throw Exception('ช่วงเวลานี้เพิ่งถูกจองไปแล้ว กรุณาเลือกเวลาอื่น');
        }
        int nextNum = (dayData?['count'] ?? 0) + 1;
        String qNo = nextNum.toString().padLeft(3, '0');
        assignedQueueNo = qNo;

        transaction.set(dayCounterRef, {
          'date': date,
          'count': nextNum,
        });

        bookedTimes[time] = apptRef.id;
        transaction.set(slotRef, {
          'staffUid': staffUid,
          'date': date,
          'bookedTimes': bookedTimes,
        });

        transaction.set(apptRef, {
          'patientUid': patientUid, 'patientName': patientName, 'queueNo': qNo,
          'doctor': doctor,
          'staffUid': staffUid,
          'date': date, 'time': time,
          'status': 'กำลังรอ', 'notes': '', 'machineId': machineId, 'machineName': machineName, 'createdAt': FieldValue.serverTimestamp(),
        });
      });

      return BookingSuccess(assignedQueueNo!);
    } catch (e) {
      return const BookingFailed();
    }
  }
}
