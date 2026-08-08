import 'package:cloud_functions/cloud_functions.dart';

/// Invite code ไม่ตรง หรือถูกใช้ไปแล้ว — โยนจาก [StaffInviteService.redeem]
class StaffInviteCodeInvalidException implements Exception {}

/// เรียก Cloud Functions callable `redeemStaffInvite` — ตรวจ + "เผา" invite
/// code พร้อมสร้าง users/{uid} (role: staff) ทั้งหมดฝั่งเซิร์ฟเวอร์ด้วย Admin
/// SDK เพื่อไม่ให้ตัวโค้ดต้องถูกอ่านได้จากฝั่ง client เลย (ดู firestore.rules
/// settings/staff_invite — admin-only read/write)
class StaffInviteService {
  StaffInviteService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  final FirebaseFunctions _functions;

  Future<void> redeem({
    required String code,
    required String fullname,
    required String email,
    required String specialization,
  }) async {
    final callable = _functions.httpsCallable('redeemStaffInvite');
    try {
      await callable.call<Map<String, dynamic>>({
        'code': code, 'fullname': fullname, 'email': email, 'specialization': specialization,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') throw StaffInviteCodeInvalidException();
      rethrow;
    }
  }
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป
final StaffInviteService staffInviteService = StaffInviteService();
