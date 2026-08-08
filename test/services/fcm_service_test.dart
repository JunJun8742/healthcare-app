import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/services/fcm_service.dart';

void main() {
  group('notificationDestination', () {
    test('null type -> no destination', () {
      expect(notificationDestination(role: 'patient', type: null), isNull);
    });

    test('patient targets route to patientQueue', () {
      for (final type in ['queue_called', 'morning_reminder', 'booking_cancelled', 'staff_ping', 'noshow_offer']) {
        expect(notificationDestination(role: 'patient', type: type), NotifDestination.patientQueue, reason: type);
      }
    });

    test('sos_new routes staff to staffSos, not patients', () {
      expect(notificationDestination(role: 'staff', type: 'sos_new'), NotifDestination.staffSos);
      expect(notificationDestination(role: 'patient', type: 'sos_new'), isNull);
    });

    test('booking_created/booking_cancelled route staff to staffQueue', () {
      expect(notificationDestination(role: 'staff', type: 'booking_created'), NotifDestination.staffQueue);
      expect(notificationDestination(role: 'staff', type: 'booking_cancelled'), NotifDestination.staffQueue);
    });

    test('admin gets no destination for any type — admin UI is user management only', () {
      for (final type in ['queue_called', 'sos_new', 'booking_created', 'booking_cancelled', 'morning_reminder', 'staff_ping', 'noshow_offer']) {
        expect(notificationDestination(role: 'admin', type: type), isNull, reason: type);
      }
    });

    test('patient-only type does not also route staff', () {
      expect(notificationDestination(role: 'staff', type: 'queue_called'), isNull);
      expect(notificationDestination(role: 'staff', type: 'morning_reminder'), isNull);
    });
  });
}
