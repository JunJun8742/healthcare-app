import 'package:flutter/material.dart';
import 'package:healthcare_app/features/admin/admin_users_screen.dart';

// ==========================================
// Admin Navigation
// ==========================================
class AdminNavigation extends StatefulWidget {
  const AdminNavigation({super.key});
  @override
  State<AdminNavigation> createState() => _AdminNavigationState();
}

class _AdminNavigationState extends State<AdminNavigation> {
  int index = 0;
  final screens = const [AdminUsersScreen()];

  @override
  Widget build(BuildContext context) {
    return screens[index];
  }
}
