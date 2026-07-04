import 'package:flutter/material.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/features/patient/home_screen.dart';
import 'package:healthcare_app/features/patient/active_queue_screen.dart';
import 'package:healthcare_app/features/patient/history_screen.dart';
import 'package:healthcare_app/features/patient/profile_screen.dart';

// ==========================================
// 4. Main Navigation (Patient)
// ==========================================
class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({super.key, this.initialIndex = 0});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int index;
  final pages = [const HomeScreen(), const ActiveQueueScreen(), const HistoryScreen(), const ProfileScreen()];

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
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: primaryGreen), label: 'หน้าแรก'),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people, color: primaryGreen), label: 'คิวของฉัน'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description, color: primaryGreen), label: 'ประวัติ'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: primaryGreen), label: 'โปรไฟล์'),
          ],
        ),
      ),
    );
  }
}
