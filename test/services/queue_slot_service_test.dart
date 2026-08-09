import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/services/queue_slot_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late QueueSlotService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = QueueSlotService(db: db);
  });

  test('docId sanitizes the date the same way AvailabilityService does', () {
    expect(service.docId(staffUid: 'staffA', date: '21/06/2569'), 'staffA_21-06-2569');
  });

  group('release', () {
    test('flips a booked time to false without touching other keys', () async {
      final ref = db.collection('queue_slots').doc('staffA_21-06-2569');
      await ref.set({
        'staffUid': 'staffA', 'date': '21/06/2569',
        'bookedTimes': {'09:00': 'apptA', '10:00': 'apptB'},
      });
      await service.release(staffUid: 'staffA', date: '21/06/2569', time: '09:00');
      final data = (await ref.get()).data()!;
      expect(data['bookedTimes']['09:00'], false);
      expect(data['bookedTimes']['10:00'], 'apptB');
    });

    test('never throws even if the doc does not exist (fire-and-forget by design)', () async {
      await expectLater(
        service.release(staffUid: 'ghost', date: '21/06/2569', time: '09:00'),
        completes,
      );
    });
  });

  group('relock', () {
    test('re-links a released time back to an appointment id', () async {
      final ref = db.collection('queue_slots').doc('staffA_21-06-2569');
      await ref.set({
        'staffUid': 'staffA', 'date': '21/06/2569',
        'bookedTimes': {'09:00': false},
      });
      await service.relock(staffUid: 'staffA', date: '21/06/2569', time: '09:00', apptId: 'apptNew');
      final data = (await ref.get()).data()!;
      expect(data['bookedTimes']['09:00'], 'apptNew');
    });
  });
}
