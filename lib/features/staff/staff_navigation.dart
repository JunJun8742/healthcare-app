import 'package:flutter/material.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/features/staff/staff_queue_screen.dart';
import 'package:healthcare_app/features/staff/staff_sos_screen.dart';
import 'package:healthcare_app/features/staff/staff_history_screen.dart';
import 'package:healthcare_app/features/staff/staff_availability_screen.dart';
import 'package:healthcare_app/features/patient/profile_screen.dart';

// =======================================================================================
// STAFF SECTION
// =======================================================================================

class StaffNavigation extends StatefulWidget {
  final int initialIndex;
  const StaffNavigation({super.key, this.initialIndex = 0});
  @override
  State<StaffNavigation> createState() => _StaffNavigationState();
}

class _StaffNavigationState extends State<StaffNavigation> {
  late int index;
  final pages = [const StaffQueueScreen(), const StaffSOSScreen(), const StaffTreatmentHistoryScreen(), const StaffAvailabilityScreen(), const ProfileScreen()];

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: NavigationBar(
          selectedIndex: index, backgroundColor: Colors.transparent, indicatorColor: lightGreen, height: 68,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt, color: primaryGreen), label: 'จัดการคิว'),
            NavigationDestination(icon: Icon(Icons.warning_amber_outlined), selectedIcon: Icon(Icons.warning_amber_rounded, color: primaryGreen), label: 'SOS'),
            NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history, color: primaryGreen), label: 'ประวัติ'),
            NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule, color: primaryGreen), label: 'เวลาว่าง'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: primaryGreen), label: 'โปรไฟล์'),
          ],
        ),
      ),
    );
  }
}
