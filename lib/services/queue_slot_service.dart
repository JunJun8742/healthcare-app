import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:healthcare_app/core/format.dart';

class QueueSlotService {
  QueueSlotService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  String docId({required String staffUid, required String date}) => '${staffUid}_${queueSlotDateKey(date)}';

  // ===== queue_slots release/re-lock helpers (shared by patient cancel & staff
  // status changes) — see firestore.rules queue_slots for the write invariants.
  // Failure here must never break the caller's cancel/undo UX, so both are
  // fire-and-forget with a debugPrint on error.
  Future<void> release({required String staffUid, required String date, required String time}) async {
    try {
      await _db.collection('queue_slots').doc(docId(staffUid: staffUid, date: date))
          .update({'bookedTimes.$time': false});
    } catch (e) {
      debugPrint('releaseQueueSlot failed: $e');
    }
  }

  Future<void> relock({required String staffUid, required String date, required String time, required String apptId}) async {
    try {
      await _db.collection('queue_slots').doc(docId(staffUid: staffUid, date: date))
          .update({'bookedTimes.$time': apptId});
    } catch (e) {
      debugPrint('relockQueueSlot failed: $e');
    }
  }
}
