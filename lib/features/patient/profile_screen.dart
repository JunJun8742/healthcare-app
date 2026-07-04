import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:healthcare_app/core/photo.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/fcm_service.dart';
import 'package:healthcare_app/services/user_service.dart';
import 'package:healthcare_app/app/app.dart';

// ==========================================
// 9. Profile Screen
// ==========================================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isUploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 400);
    if (picked == null || !mounted) return;

    setState(() => isUploading = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      final base64Str = encodePhotoBase64(bytes);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await users.updatePhotoBase64(uid: uid, photoBase64: base64Str);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Photo upload error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อินเทอร์เน็ตขัดข้อง กรุณาตรวจสอบการเชื่อมต่อ'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการออกจากระบบ', style: TextStyle(fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await removeFcmTokenBeforeLogout();
              await FirebaseAuth.instance.signOut();
              if (ctx.mounted) Navigator.pushAndRemoveUntil(ctx, MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
            },
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์ของฉัน'), automaticallyImplyLeading: false),
      body: FutureBuilder<DocumentSnapshot>(
        future: users.getUser(user?.uid),
        builder: (context, snap) {
          String name = 'กำลังโหลด...';
          String role = 'patient';
          String spec = '';
          String photoBase64 = '';
          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data() as Map<String, dynamic>;
            name = d['fullname'] ?? 'ผู้ใช้งาน';
            role = d['role'] ?? 'patient';
            spec = d['specialization'] ?? '';
            photoBase64 = d['photoBase64'] ?? '';
          }
          bool isStaff = role == 'staff';
          Color accentColor = isStaff ? Colors.orange : primaryGreen;
          final photoBytes = tryDecodePhotoBase64(photoBase64);
          ImageProvider? photoImage = photoBytes != null ? MemoryImage(photoBytes) : null;

          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(alignment: Alignment.bottomRight, children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: accentColor.withValues(alpha: 0.2),
                  backgroundImage: photoImage,
                  child: photoImage == null ? Icon(isStaff ? Icons.medical_services : Icons.person, size: 55, color: accentColor) : null,
                ),
                GestureDetector(
                  onTap: isUploading ? null : _pickAndUpload,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: isUploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              Text(name, style: GoogleFonts.prompt(fontSize: 22, fontWeight: FontWeight.bold)),
              if (isStaff && spec.isNotEmpty) Text(spec, style: GoogleFonts.prompt(fontSize: 14, color: Colors.orange)),
              Text(user?.email ?? '-', style: GoogleFonts.prompt(fontSize: 16, color: Colors.grey)),
              if (isStaff) Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20)), child: const Text('นักกายภาพบำบัด', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                icon: const Icon(Icons.logout),
                label: const Text('ออกจากระบบ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () => _confirmLogout(context),
              ),
            ]),
          );
        },
      ),
    );
  }
}
