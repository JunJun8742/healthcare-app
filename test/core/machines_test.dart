import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_app/core/machines.dart';

void main() {
  group('knownMachines', () {
    test('is non-empty and every id is unique', () {
      expect(knownMachines, isNotEmpty);
      final ids = knownMachines.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('machineStateFor', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('never sent any data (lastUpdated null) -> unknown', () {
      expect(machineStateFor(isActive: null, lastUpdated: null, now: now), MachineState.unknown);
    });

    test('heartbeat stale (30s+) -> unknown regardless of isActive', () {
      final stale = now.subtract(const Duration(seconds: 31));
      expect(machineStateFor(isActive: true, lastUpdated: stale, now: now), MachineState.unknown);
      expect(machineStateFor(isActive: false, lastUpdated: stale, now: now), MachineState.unknown);
    });

    test('fresh heartbeat + is_active false -> online (connected, not treating)', () {
      final fresh = now.subtract(const Duration(seconds: 5));
      expect(machineStateFor(isActive: false, lastUpdated: fresh, now: now), MachineState.online);
    });

    test('fresh heartbeat + is_active true -> inUse', () {
      final fresh = now.subtract(const Duration(seconds: 5));
      expect(machineStateFor(isActive: true, lastUpdated: fresh, now: now), MachineState.inUse);
    });

    test('fresh heartbeat + is_active missing (null) -> online, not inUse (defaults to not-in-use)', () {
      final fresh = now.subtract(const Duration(seconds: 5));
      expect(machineStateFor(isActive: null, lastUpdated: fresh, now: now), MachineState.online);
    });
  });
}
