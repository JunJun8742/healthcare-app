import 'package:cloud_firestore/cloud_firestore.dart';

class SosService {
  SosService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<void> sendAlert({required String patientUid, required String patientName, required String issue}) async {
    await _db.collection('sos_alerts').add({'patientUid': patientUid, 'patientName': patientName, 'issue': issue, 'status': 'รอรับเรื่อง', 'createdAt': FieldValue.serverTimestamp()});
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> pendingAlerts() =>
      _db.collection('sos_alerts').where('status', isEqualTo: 'รอรับเรื่อง').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> resolvedAlerts() =>
      _db.collection('sos_alerts').where('status', isEqualTo: 'รับเรื่องแล้ว').snapshots();

  Future<void> resolveAlert(String alertId) async {
    await _db.collection('sos_alerts').doc(alertId).update({'status': 'รับเรื่องแล้ว', 'resolvedAt': FieldValue.serverTimestamp()});
  }
}
