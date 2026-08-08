import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/core/format.dart';

void main() {
  group('thaiBuddhistDate', () {
    test('converts Gregorian year to Buddhist era (+543) with zero-padding', () {
      expect(thaiBuddhistDate(DateTime(2026, 1, 5)), '05/01/2569');
      expect(thaiBuddhistDate(DateTime(2026, 12, 31)), '31/12/2569');
    });
  });

  group('queueSlotDateKey', () {
    test('replaces every slash so the string is safe as a single Firestore doc-ID segment', () {
      // This is the exact bug class documented in CLAUDE.md: an un-sanitized
      // '/' gets parsed by CollectionReference.doc(path) as a path
      // separator, silently writing into a nested subcollection instead of
      // the intended flat doc.
      expect(queueSlotDateKey('21/06/2569'), '21-06-2569');
      expect(queueSlotDateKey('21/06/2569').contains('/'), isFalse);
    });
  });

  group('isMachineStale', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('no record at all -> not stale (nothing to be stale about)', () {
      expect(isMachineStale(lastUpdated: null, recordExists: false, now: now), isFalse);
    });

    test('record exists but heartbeat missing -> stale', () {
      expect(isMachineStale(lastUpdated: null, recordExists: true, now: now), isTrue);
    });

    test('heartbeat just under the timeout -> not stale', () {
      final lastUpdated = now.subtract(const Duration(seconds: 29));
      expect(isMachineStale(lastUpdated: lastUpdated, recordExists: true, now: now), isFalse);
    });

    test('heartbeat at/over the timeout -> stale', () {
      final lastUpdated = now.subtract(const Duration(seconds: 30));
      expect(isMachineStale(lastUpdated: lastUpdated, recordExists: true, now: now), isTrue);
    });

    test('respects a custom timeout', () {
      final lastUpdated = now.subtract(const Duration(seconds: 45));
      expect(isMachineStale(lastUpdated: lastUpdated, recordExists: true, now: now, timeout: const Duration(minutes: 1)), isFalse);
      expect(isMachineStale(lastUpdated: lastUpdated, recordExists: true, now: now, timeout: const Duration(seconds: 30)), isTrue);
    });
  });

  group('relativeTimeTh', () {
    test('null timestamp -> empty string', () {
      expect(relativeTimeTh(null), '');
    });

    test('just now -> เมื่อสักครู่', () {
      expect(relativeTimeTh(Timestamp.now()), 'เมื่อสักครู่');
    });
  });

  group('compareCreatedAtDesc', () {
    test('newest first: later timestamp sorts before earlier', () {
      final earlier = Timestamp.fromMillisecondsSinceEpoch(1000);
      final later = Timestamp.fromMillisecondsSinceEpoch(2000);
      expect(compareCreatedAtDesc(later, earlier), lessThan(0));
      expect(compareCreatedAtDesc(earlier, later), greaterThan(0));
    });

    test('null createdAt (still writing) sorts last', () {
      final real = Timestamp.fromMillisecondsSinceEpoch(1000);
      expect(compareCreatedAtDesc(null, real), greaterThan(0));
      expect(compareCreatedAtDesc(real, null), lessThan(0));
    });
  });
}
