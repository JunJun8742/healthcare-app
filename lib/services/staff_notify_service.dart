import 'package:cloud_functions/cloud_functions.dart';

/// เรียก Cloud Functions callable `pingPatient` — ให้ staff แจ้งเตือนคนไข้ของ
/// คิวนั้นๆ ได้เอง แยกจากแจ้งเตือนอัตโนมัติตอนเปลี่ยนสถานะ (onQueueCalled ฯลฯ)
class StaffNotifyService {
  StaffNotifyService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  final FirebaseFunctions _functions;

  Future<void> pingPatient(String apptId) async {
    final callable = _functions.httpsCallable('pingPatient');
    await callable.call<Map<String, dynamic>>({'apptId': apptId});
  }
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป
final StaffNotifyService staffNotify = StaffNotifyService();
