import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:healthcare_app/core/photo.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/widgets.dart';
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

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบบัญชีและข้อมูลของฉัน', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: const Text('การกระทำนี้จะลบบัญชีและประวัติการจองคิวทั้งหมดของคุณอย่างถาวร ไม่สามารถกู้คืนได้ ต้องการดำเนินการต่อหรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showReauthDialog(context);
            },
            child: const Text('ดำเนินการต่อ'),
          ),
        ],
      ),
    );
  }

  void _showReauthDialog(BuildContext context) {
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool loading = false;
    String? error;

    Future<void> submit(StateSetter setDialogState, BuildContext dialogCtx) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email == null) return;
      setDialogState(() { loading = true; error = null; });
      try {
        // Re-verify identity via email+password before an irreversible
        // delete — Firebase also enforces this itself (throws
        // requires-recent-login on a stale session) but we ask up front so
        // the failure mode is a normal inline error, not a stuck retry loop.
        await user!.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: passCtrl.text),
        );
        final uid = user.uid;
        // Order matters: clean up Firestore (token removal, then the
        // account's own data) BEFORE deleting the Auth account itself —
        // once the Auth account is gone, request.auth.uid no longer matches
        // anything and every one of these writes would be denied.
        await removeFcmTokenBeforeLogout();
        await users.deleteOwnAccount(uid);
        await user.delete();
        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
        if (context.mounted) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
        }
      } on FirebaseAuthException catch (e) {
        setDialogState(() {
          loading = false;
          error = e.code == 'wrong-password' || e.code == 'invalid-credential'
              ? 'รหัสผ่านไม่ถูกต้อง'
              : 'ยืนยันตัวตนไม่สำเร็จ (${e.code})';
        });
      } catch (e) {
        setDialogState(() { loading = false; error = 'เกิดข้อผิดพลาด กรุณาลองใหม่'; });
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('ยืนยันตัวตนอีกครั้ง', style: TextStyle(fontWeight: FontWeight.bold)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('กรอกรหัสผ่านของอีเมล ${FirebaseAuth.instance.currentUser?.email ?? ''} เพื่อยืนยันก่อนลบบัญชี'),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              autofocus: true,
              onChanged: (_) => setDialogState(() {}),
              decoration: InputDecoration(
                hintText: 'รหัสผ่าน',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setDialogState(() => obscure = !obscure),
                ),
              ),
            ),
            if (error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(onPressed: loading ? null : () => Navigator.pop(dialogCtx), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: loading || passCtrl.text.isEmpty ? null : () => submit(setDialogState, dialogCtx),
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('ยืนยันและลบบัญชี'),
            ),
          ],
        ),
      ),
    );
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

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: kGapL),
            child: Column(children: [
              const SizedBox(height: kGapM),
              const EmailVerificationBanner(),
              Expanded(child: Center(
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
              // Self-service account deletion — patient-only. Staff accounts
              // are provisioned via admin-issued invite code and managed by
              // admin (AdminUsersScreen), so self-delete isn't exposed there
              // to avoid a staff account wiping data other patients depend on.
              if (!isStaff) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: Text('ลบบัญชีและข้อมูลของฉัน', style: GoogleFonts.notoSansThai(fontSize: 13)),
                  onPressed: () => _confirmDeleteAccount(context),
                ),
              ],
            ]),
          )),
            ]),
          );
        },
      ),
    );
  }
}
