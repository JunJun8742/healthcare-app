import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/user_service.dart';

// ==========================================
// 3. Staff Register Screen (ใหม่)
// ==========================================
class StaffRegisterScreen extends StatefulWidget {
  const StaffRegisterScreen({super.key});
  @override
  State<StaffRegisterScreen> createState() => _StaffRegisterScreenState();
}

class _StaffRegisterScreenState extends State<StaffRegisterScreen> {
  final fullnameCtrl = TextEditingController();
  final specCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final inviteCtrl = TextEditingController();
  bool loading = false;
  bool obscure = true;

  Future<void> register() async {
    if ([fullnameCtrl, specCtrl, emailCtrl, passCtrl, inviteCtrl].any((c) => c.text.isEmpty)) {
      _snack('กรุณากรอกข้อมูลให้ครบทุกช่อง');
      return;
    }
    if (passCtrl.text.length < 6) { _snack('รหัสผ่านต้องมีอย่างน้อย 6 ตัว'); return; }

    setState(() => loading = true);
    try {
      // ตรวจ invite code
      String? correctCode = await users.fetchStaffInviteCode();
      if (correctCode == null) { _snack('ระบบ Invite Code ยังไม่ได้ตั้งค่า กรุณาติดต่อผู้ดูแลระบบ'); return; }
      if (inviteCtrl.text.trim() != correctCode) { _snack('Invite Code ไม่ถูกต้อง กรุณาติดต่อผู้ดูแลระบบ'); return; }

      // สร้างบัญชี
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(), password: passCtrl.text.trim(),
      );
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'fullname': fullnameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'role': 'staff',
        'specialization': specCtrl.text.trim(),
        'inviteCode': inviteCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สมัครบัญชีนักกายภาพสำเร็จ!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(e.message ?? 'เกิดข้อผิดพลาด');
    } on FirebaseException catch (e) {
      if (mounted) _snack('อ่านข้อมูล Invite Code ไม่สำเร็จ (${e.code}) กรุณาตรวจสอบสิทธิ์การเข้าถึง Firestore');
    } catch (e) {
      debugPrint('Staff register error: $e');
      if (mounted) _snack('เกิดข้อผิดพลาด กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    setState(() => loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xffEEF8F2), Color(0xffFFFFFF)]),
          ),
          child: SafeArea(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Logo with soft glow + Staff badge ──
            Center(child: SizedBox(
              width: 130, height: 130,
              child: Stack(alignment: Alignment.center, children: [
                Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xff52b788).withValues(alpha: 0.10))),
                Container(width: 98, height: 98, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xff52b788).withValues(alpha: 0.12))),
                Container(
                  width: 78, height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.medical_services_rounded, color: Color(0xff2d6a4f), size: 32),
                ),
                Positioned(
                  bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xff52b788), Color(0xff1b4332)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Text('STAFF', style: GoogleFonts.prompt(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 18),
            Center(child: Column(children: [
              Text('สมัครบัญชีเจ้าหน้าที่', style: GoogleFonts.playfairDisplay(fontSize: 27, fontWeight: FontWeight.w700, color: const Color(0xff2d6a4f), height: 1.2)),
              const SizedBox(height: 4),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(colors: [Color(0xff1b4332), Color(0xff40916c)]).createShader(b),
                child: Text('สำหรับนักกายภาพบำบัดเท่านั้น', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ])),
            const SizedBox(height: 28),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(child: Container(height: 1, color: const Color(0xffCFE9DB))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('ข้อมูลบัญชี', style: GoogleFonts.notoSansThai(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xff52b788), letterSpacing: 0.3)),
                ),
                Expanded(child: Container(height: 1, color: const Color(0xffCFE9DB))),
              ]),
              const SizedBox(height: 22),
              _sLabel('ชื่อ-นามสกุล'),
              const SizedBox(height: 8),
              _sField('กรอกชื่อ-นามสกุล', Icons.person_outline_rounded, fullnameCtrl),
              const SizedBox(height: 16),
              _sLabel('ความเชี่ยวชาญ'),
              const SizedBox(height: 8),
              _sField('เช่น กายภาพบำบัด', Icons.medical_information_outlined, specCtrl),
              const SizedBox(height: 16),
              _sLabel('อีเมล'),
              const SizedBox(height: 8),
              _sField('กรอกอีเมล', Icons.email_outlined, emailCtrl, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _sLabel('รหัสผ่าน'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: TextField(
                  controller: passCtrl, obscureText: obscure,
                  style: GoogleFonts.notoSansThai(fontSize: 15, color: textDark, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'กรอกรหัสผ่าน (อย่างน้อย 6 ตัว)', hintStyle: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(color: const Color(0xffE6F4EA), borderRadius: BorderRadius.circular(11)),
                      child: const Icon(Icons.lock_outline_rounded, color: Color(0xff2d6a4f), size: 18),
                    ),
                    suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade400, size: 20), onPressed: () => setState(() => obscure = !obscure)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xff74c69d), width: 1.6)),
                    filled: true, fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Invite Code
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade200, width: 1.2),
                  boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.vpn_key_rounded, color: Colors.amber.shade700, size: 16),
                    const SizedBox(width: 6),
                    Text('Invite Code', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w700, color: Colors.amber.shade800, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text('(จำเป็น)', style: GoogleFonts.notoSansThai(color: Colors.amber.shade600, fontSize: 11)),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
                    child: TextField(
                      controller: inviteCtrl,
                      style: GoogleFonts.notoSansThai(fontSize: 14, color: textDark),
                      decoration: InputDecoration(
                        hintText: 'กรอก Invite Code จากผู้ดูแลระบบ',
                        hintStyle: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: loading ? null : register,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff52b788), Color(0xff2d6a4f), Color(0xff1b4332)]),
                    boxShadow: [
                      BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 8)),
                      BoxShadow(color: const Color(0xff52b788).withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, -2)),
                    ],
                  ),
                  child: loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('สมัครบัญชีนักกายภาพ', style: GoogleFonts.notoSansThai(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                          child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                        ),
                      ]),
                ),
              ),
              const SizedBox(height: 22),
              Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('มีบัญชีแล้ว? ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 14)),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('เข้าสู่ระบบ', style: GoogleFonts.notoSansThai(color: const Color(0xff2d6a4f), fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ])),
          ]),
        )),
        ),
        // ── Floating back button (bottom-left) ──
        Positioned(
          left: 24, bottom: 6,
          child: SafeArea(
            top: false,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xffB7E4C7)),
                  boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xff2d6a4f), size: 20),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _sLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(text, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w700, fontSize: 13.5, color: const Color(0xff1b4332))),
  );

  Widget _sField(String hint, IconData icon, TextEditingController ctrl, {TextInputType? keyboardType}) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 4))],
    ),
    child: TextField(
      controller: ctrl, keyboardType: keyboardType,
      style: GoogleFonts.notoSansThai(fontSize: 15, color: textDark, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint, hintStyle: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Container(
          margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: const Color(0xffE6F4EA), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: const Color(0xff2d6a4f), size: 18),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xff74c69d), width: 1.6)),
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );

}
