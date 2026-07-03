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

  Future<String?> fetchStaffInviteCode() async {
    DocumentSnapshot inviteDoc = await _db.collection('settings').doc('staff_invite').get();
    if (!inviteDoc.exists) return null;
    return (inviteDoc.data() as Map<String, dynamic>)['invite_code'] ?? '';
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
