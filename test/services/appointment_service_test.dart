import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/services/appointment_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AppointmentService service;

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = AppointmentService(db: db);
    await db.collection('users').doc('patient1').set({'fullname': 'สมชาย ใจดี'});
    await db.collection('users').doc('patient2').set({'fullname': 'สมหญิง รักดี'});
  });

  group('createBooking', () {
    test('first booking of the day for a staff succeeds with queueNo 001', () async {
      final outcome = await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      expect(outcome, isA<BookingSuccess>());
      expect((outcome as BookingSuccess).queueNo, '001');

      final appts = await db.collection('appointments').get();
      expect(appts.docs, hasLength(1));
      expect(appts.docs.first.data()['status'], QueueStatus.waiting);
      expect(appts.docs.first.data()['patientName'], 'สมชาย ใจดี');
    });

    test('queueNo counter is shared across ALL staff for the same day, not per-staff', () async {
      final first = await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      final second = await service.createBooking(
        patientUid: 'patient2', doctor: 'หมอบี', staffUid: 'staffB',
        date: '21/06/2569', time: '09:00', machineId: 'm2', machineName: 'เครื่อง 2',
      );
      expect((first as BookingSuccess).queueNo, '001');
      expect((second as BookingSuccess).queueNo, '002');
    });

    test('a patient with an active (waiting/called/treating) appointment cannot book a second one', () async {
      await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      final second = await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '10:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      expect(second, isA<BookingBlockedByActiveQueue>());

      // Only the first booking's writes should exist — the block check must
      // run before the transaction touches queue_days/queue_slots.
      final appts = await db.collection('appointments').get();
      expect(appts.docs, hasLength(1));
    });

    test('a cancelled appointment does not block a new booking for the same patient', () async {
      final first = await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      final firstDoc = (await db.collection('appointments').get()).docs.first;
      await firstDoc.reference.update({'status': QueueStatus.cancelled});

      final second = await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '10:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      expect(first, isA<BookingSuccess>());
      expect(second, isA<BookingSuccess>());
    });

    test('two different patients cannot both book the same staff+date+time slot', () async {
      final first = await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      final second = await service.createBooking(
        patientUid: 'patient2', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      expect(first, isA<BookingSuccess>());
      expect(second, isA<BookingFailed>());

      // queue_days must NOT have advanced for the failed attempt — otherwise
      // the next real booking would skip a queue number.
      final dayDoc = await db.collection('queue_days').doc('21-06-2569').get();
      expect(dayDoc.data()!['count'], 1);
    });

    test('the same time slot can be reused once released (bookedTimes[time] == false)', () async {
      await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      final slotRef = db.collection('queue_slots').doc('staffA_21-06-2569');
      await slotRef.update({'bookedTimes.09:00': false});

      final second = await service.createBooking(
        patientUid: 'patient2', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      expect(second, isA<BookingSuccess>());
    });

    test('date with a slash is sanitized before being used as a doc-ID segment', () async {
      await service.createBooking(
        patientUid: 'patient1', doctor: 'หมอเอ', staffUid: 'staffA',
        date: '21/06/2569', time: '09:00', machineId: 'm1', machineName: 'เครื่อง 1',
      );
      // If sanitization were missing, this doc simply wouldn't exist at this
      // flat path — the write would have silently gone to a nested
      // subcollection instead (see queueSlotDateKey's docs).
      final dayDoc = await db.collection('queue_days').doc('21-06-2569').get();
      expect(dayDoc.exists, isTrue);
    });
  });

  group('hasActiveAppointment', () {
    test('true for waiting/called/treating, false for done/cancelled', () async {
      for (final status in QueueStatus.terminal) {
        await db.collection('appointments').add({'patientUid': 'p_terminal', 'status': status});
      }
      expect(await service.hasActiveAppointment('p_terminal'), isFalse);

      for (final status in QueueStatus.active) {
        final ref = db.collection('appointments').doc();
        await ref.set({'patientUid': 'p_active_$status', 'status': status});
        expect(await service.hasActiveAppointment('p_active_$status'), isTrue);
      }
    });
  });
}
