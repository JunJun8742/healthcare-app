import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  UserService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String? uid) =>
      _db.collection('users').doc(uid).get();

  Stream<QuerySnapshot<Map<String, dynamic>>> usersByRole(String role) =>
      _db.collection('users').where('role', isEqualTo: role).snapshots();

  Future<List<Map<String, dynamic>>> staffUsers() async {
    var snap = await _db.collection('users').where('role', isEqualTo: 'staff').get();
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<void> updatePhotoBase64({required String uid, required String photoBase64}) async {
    await _db.collection('users').doc(uid).update({'photoBase64': photoBase64});
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> staffInviteCodeStream() =>
      _db.collection('settings').doc('staff_invite').snapshots();

  /// สุ่มโค้ดใหม่ (6 ตัว ตัวใหญ่+ตัวเลข ไม่มี 0/O/1/I กันสับสน) แล้วบันทึกทับของเดิม
  /// พร้อมรีเซ็ต used กลับเป็น false เสมอ (โค้ดใหม่ต้องใช้ได้ 1 ครั้ง) — ต้องเป็น
  /// admin เท่านั้น ตาม firestore.rules (settings/staff_invite)
  Future<String> generateNewStaffInviteCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    await _db.collection('settings').doc('staff_invite').set({
      'invite_code': code,
      'used': false,
      'usedBy': FieldValue.delete(),
      'usedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return code;
  }

  /// ลบบัญชี+ข้อมูลของ "ตัวเอง" เท่านั้น (self-service, PDPA right-to-erasure)
  /// — ต่างจาก [deleteUserCascade] (admin-only) ตรงที่ลบเฉพาะ appointments ที่
  /// ตัวเองเป็น "ผู้ป่วย" (patientUid) เท่านั้น ไม่แตะ appointments/ที่ตัวเองเป็น
  /// staffUid หรือ staff_availability — กันไม่ให้บัญชี staff ที่ลบตัวเองไปลบ
  /// ประวัติการรักษาของผู้ป่วยคนอื่นโดยไม่ตั้งใจ (ดู firestore.rules ที่คุมเรื่องนี้
  /// อยู่แล้วในระดับ rule — เมธอดนี้แค่ตรงกับ scope ที่ rule อนุญาต)
  Future<void> deleteOwnAccount(String uid) async {
    final batch = _db.batch();
    batch.delete(_db.collection('users').doc(uid));
    final appts = await _db.collection('appointments').where('patientUid', isEqualTo: uid).get();
    for (var d in appts.docs) { batch.delete(d.reference); }
    await batch.commit();
  }

  Future<void> deleteUserCascade(String uid) async {
    final batch = _db.batch();
    batch.delete(_db.collection('users').doc(uid));
    final appts = await _db.collection('appointments').where('patientUid', isEqualTo: uid).get();
    for (var d in appts.docs) { batch.delete(d.reference); }
    final apptsSt = await _db.collection('appointments').where('staffUid', isEqualTo: uid).get();
    for (var d in apptsSt.docs) { batch.delete(d.reference); }
    final avail = await _db.collection('staff_availability').where('staffUid', isEqualTo: uid).get();
    for (var d in avail.docs) { batch.delete(d.reference); }
    await batch.commit();
  }
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป (default Firestore)
final UserService users = UserService();
