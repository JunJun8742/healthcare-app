import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<QuerySnapshot<Map<String, dynamic>>> forUser(String? uid) =>
      _db.collection('notifications').where('uid', isEqualTo: uid).snapshots();

  // ไม่ limit(1) แล้ว — ฝั่ง caller ที่ต้องการแค่ "มี unread ไหม" ใช้ docs.isNotEmpty
  // ได้เหมือนเดิม ส่วนที่ต้องการนับจำนวนจริง (เช่น badge ตัวเลขหน้า User) ใช้
  // docs.length ได้จาก stream เดียวกัน
  Stream<QuerySnapshot<Map<String, dynamic>>> unreadProbe(String? uid) => _db
      .collection('notifications')
      .where('uid', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .snapshots();

  Future<void> markRead(DocumentReference<Object?> ref) => ref.update({'read': true});
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป (default Firestore)
final NotificationService notifications = NotificationService();
