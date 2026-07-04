import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/photo.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/user_service.dart';
import 'package:healthcare_app/services/fcm_service.dart';

// ==========================================
// Admin: Users Screen
// ==========================================
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _deleteUser(BuildContext ctx, String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.delete_rounded, color: Colors.red.shade600, size: 20)),
          const SizedBox(width: 10),
          const Expanded(child: Text('ลบบัญชีผู้ใช้', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ]),
        content: Text('ต้องการลบบัญชีของ "$name" ออกจากระบบ?\n\nข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้', style: GoogleFonts.notoSansThai(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('ยกเลิก', style: GoogleFonts.notoSansThai(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ลบบัญชี', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await users.deleteUserCascade(uid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ลบบัญชี "$name" เรียบร้อยแล้ว'), backgroundColor: primaryGreen));
    } catch (e) {
      debugPrint('Delete account error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      body: Column(children: [
        Container(
          color: Colors.white,
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('จัดการบัญชีผู้ใช้', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                  Text('Admin Panel', style: GoogleFonts.notoSansThai(fontSize: 11, color: Colors.grey.shade400)),
                ]),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await removeFcmTokenBeforeLogout();
                    await FirebaseAuth.instance.signOut();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.logout_rounded, color: Colors.red.shade600, size: 20),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                height: 40,
                decoration: BoxDecoration(color: bgWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'ค้นหาชื่อ...',
                    hintStyle: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 18),
                    border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            TabBar(
              controller: _tab,
              labelColor: primaryGreen, unselectedLabelColor: Colors.grey.shade500,
              indicatorColor: primaryGreen, indicatorWeight: 3, indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.notoSansThai(fontSize: 13),
              tabs: const [Tab(text: 'ผู้ป่วย'), Tab(text: 'เจ้าหน้าที่')],
            ),
          ])),
        ),
        const Divider(height: 1),
        Expanded(child: TabBarView(controller: _tab, children: [
          _userList('patient'),
          _userList('staff'),
        ])),
      ]),
    );
  }

  Widget _userList(String role) => StreamBuilder<QuerySnapshot>(
    stream: users.usersByRole(role),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
      final docs = (snap.data?.docs ?? []).where((d) {
        final name = ((d.data() as Map)['fullname'] ?? '').toString().toLowerCase();
        final email = ((d.data() as Map)['email'] ?? '').toString().toLowerCase();
        return _search.isEmpty || name.contains(_search) || email.contains(_search);
      }).toList();
      if (docs.isEmpty) {
        return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.person_off_rounded, color: Colors.grey.shade300, size: 56),
          const SizedBox(height: 12),
          Text('ไม่พบผู้ใช้', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 15)),
        ]));
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final data = docs[i].data() as Map<String, dynamic>;
          final uid = docs[i].id;
          final name = data['fullname'] ?? 'ไม่ระบุชื่อ';
          final email = data['email'] ?? '';
          final photo = data['photoBase64'] ?? '';
          final photoBytes = tryDecodePhotoBase64(photo);
          ImageProvider? photoImg = photoBytes != null ? MemoryImage(photoBytes) : null;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                CircleAvatar(radius: 26, backgroundColor: lightGreen, backgroundImage: photoImg, child: photoImg == null ? Text(name.toString().characters.first, style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 16)) : null),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                  const SizedBox(height: 2),
                  Text(email, style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)),
                ])),
                GestureDetector(
                  onTap: () => _deleteUser(context, uid, name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 16),
                      const SizedBox(width: 5),
                      Text('ลบ', style: GoogleFonts.notoSansThai(color: Colors.red.shade600, fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                  ),
                ),
              ]),
            ),
          );
        },
      );
    },
  );
} 
