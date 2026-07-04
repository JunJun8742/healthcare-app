import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/status.dart';

class SosService {
  SosService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<void> sendAlert({required String patientUid, required String patientName, required String issue}) async {
    await _db.collection('sos_alerts').add({'patientUid': patientUid, 'patientName': patientName, 'issue': issue, 'status': SosStatus.pending, 'createdAt': FieldValue.serverTimestamp()});
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> pendingAlerts() =>
      _db.collection('sos_alerts').where('status', isEqualTo: SosStatus.pending).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> resolvedAlerts() =>
      _db.collection('sos_alerts').where('status', isEqualTo: SosStatus.resolved).snapshots();

  Future<void> resolveAlert(String alertId) async {
    await _db.collection('sos_alerts').doc(alertId).update({'status': SosStatus.resolved, 'resolvedAt': FieldValue.serverTimestamp()});
  }
}

/// อินสแตนซ์กลางที่แชร์ทั้งแอป (default Firestore)
final SosService sos = SosService();
