import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/core/status.dart';

void main() {
  group('QueueStatus', () {
    test('stored Firestore string values must never change — many docs already exist with these exact strings', () {
      expect(QueueStatus.waiting, 'กำลังรอ');
      expect(QueueStatus.called, 'เรียกคิว');
      expect(QueueStatus.treating, 'กำลังรักษา');
      expect(QueueStatus.done, 'เสร็จสิ้น');
      expect(QueueStatus.cancelled, 'ยกเลิก');
    });

    test('active/terminal groupings are disjoint and cover every status', () {
      final all = {...QueueStatus.active, ...QueueStatus.terminal};
      expect(all, {QueueStatus.waiting, QueueStatus.called, QueueStatus.treating, QueueStatus.done, QueueStatus.cancelled});
      expect(QueueStatus.active.toSet().intersection(QueueStatus.terminal.toSet()), isEmpty);
    });
  });

  group('statusInfo', () {
    test('every known QueueStatus value maps to a non-empty label', () {
      for (final status in [...QueueStatus.active, ...QueueStatus.terminal]) {
        expect(statusInfo(status).label, isNotEmpty);
      }
    });

    test('treating label is decoupled from the stored value (display wording changed independently)', () {
      // QueueStatus.treating's Firestore value is 'กำลังรักษา' but the
      // display label was reworded to 'เข้ารับบริการแล้ว' — CLAUDE.md is
      // explicit that only the label may change, never the stored value.
      expect(statusInfo(QueueStatus.treating).label, 'เข้ารับบริการแล้ว');
    });

    test('unknown status falls back to the raw string as the label instead of throwing', () {
      final info = statusInfo('ไม่มีในระบบ');
      expect(info.label, 'ไม่มีในระบบ');
    });
  });
}
