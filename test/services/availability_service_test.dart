import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/services/availability_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AvailabilityService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = AvailabilityService(db: db);
  });

  group('docId', () {
    test('sanitizes the Thai date so it never contains a raw slash', () {
      // The exact bug documented in CLAUDE.md: an un-sanitized '/' is parsed
      // by CollectionReference.doc(path) as a path separator, silently
      // writing into a nested subcollection with no matching security rule
      // instead of a flat staff_availability doc.
      final id = service.docId(staffUid: 'staffA', date: '21/06/2569');
      expect(id, 'staffA_21-06-2569');
      expect(id.contains('/'), isFalse);
    });
  });

  group('staffTimes vs openTimes', () {
    test('returns null (not empty set) when nothing has ever been saved — distinguishes "never saved" from "saved as empty"', () async {
      expect(await service.staffTimes(staffUid: 'staffA', date: '21/06/2569'), isNull);
      expect(await service.openTimes(staffUid: 'staffA', date: '21/06/2569'), isEmpty);
    });

    test('saveTimes then staffTimes/openTimes round-trip the same set', () async {
      await service.saveTimes(staffUid: 'staffA', date: '21/06/2569', times: ['09:00', '10:00']);
      expect(await service.staffTimes(staffUid: 'staffA', date: '21/06/2569'), {'09:00', '10:00'});
      expect(await service.openTimes(staffUid: 'staffA', date: '21/06/2569'), ['09:00', '10:00']);
    });

    test('saving an explicit empty list is remembered as "locked, no times open" — not null', () async {
      await service.saveTimes(staffUid: 'staffA', date: '21/06/2569', times: []);
      expect(await service.staffTimes(staffUid: 'staffA', date: '21/06/2569'), isNotNull);
      expect(await service.staffTimes(staffUid: 'staffA', date: '21/06/2569'), isEmpty);
    });
  });

  group('bookedTimes', () {
    test('reads from queue_slots, not staff_availability — booked status is derived from the slot lock', () async {
      await db.collection('queue_slots').doc('staffA_21-06-2569').set({
        'staffUid': 'staffA', 'date': '21/06/2569',
        'bookedTimes': {'09:00': 'appt123', '10:00': false},
      });
      final result = await service.bookedTimes(staffUid: 'staffA', date: '21/06/2569');
      expect(result['09:00'], 'appt123');
      expect(result['10:00'], false);
    });

    test('missing queue_slots doc returns an empty map, not an error', () async {
      final result = await service.bookedTimes(staffUid: 'staffA', date: '21/06/2569');
      expect(result, isEmpty);
    });
  });
}
