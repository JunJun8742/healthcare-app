import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<QuerySnapshot<Map<String, dynamic>>> forUser(String? uid) =>
      _db.collection('notifications').where('uid', isEqualTo: uid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> unreadProbe(String? uid) => _db
      .collection('notifications')
      .where('uid', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .limit(1)
      .snapshots();

  Future<void> markRead(DocumentReference<Object?> ref) => ref.update({'read': true});
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป (default Firestore)
final NotificationService notifications = NotificationService();
