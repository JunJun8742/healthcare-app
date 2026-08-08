import 'package:cloud_functions/cloud_functions.dart';

/// เรียก Cloud Functions callable `respondToNoShowOffer` — ตอบรับ/ปฏิเสธคำถาม
/// "สนใจเข้ารับบริการไวขึ้นไหม" เมื่อคิวก่อนหน้าไม่มาตามนัดเกิน 10 นาที
/// ไม่มีการสลับคิว/เวลาใดๆ ทั้งสิ้น — แค่บันทึกว่าคนไข้เลือกเวลาไหน (หรือไม่สนใจ)
class NoShowOfferService {
  NoShowOfferService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  final FirebaseFunctions _functions;

  /// [chosenTime] ต้องตรงกับหนึ่งใน noShowOfferOptions ของคิวนั้น — ส่ง null เพื่อปฏิเสธ (ไม่สนใจ)
  Future<void> respond({required String apptId, required String? chosenTime}) async {
    final callable = _functions.httpsCallable('respondToNoShowOffer');
    await callable.call<Map<String, dynamic>>({'apptId': apptId, 'chosenTime': chosenTime});
  }
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป
final NoShowOfferService noShowOfferService = NoShowOfferService();
