import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';

// ==========================================
// 2. Register Screen (Patient)
// ==========================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final fullnameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;

  Future<void> register() async {
    if (fullnameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรอกข้อมูลให้ครบ และรหัสผ่านต้องมีอย่างน้อย 6 ตัว')));
      return;
    }
    try {
      setState(() => loading = true);
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(), password: passCtrl.text.trim(),
      );
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'fullname': fullnameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'role': 'patient',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สมัครสมาชิกสำเร็จ!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'เกิดข้อผิดพลาด')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _obscure = true;

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
            // ── Logo with soft glow ──
            Center(child: SizedBox(
              width: 130, height: 130,
              child: Stack(alignment: Alignment.center, children: [
                Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xff52b788).withValues(alpha: 0.10))),
                Container(width: 98, height: 98, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xff52b788).withValues(alpha: 0.12))),
                Container(
                  width: 78, height: 78,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  child: Image.asset('assets/hart.png', fit: BoxFit.contain),
                ),
              ]),
            )),
            const SizedBox(height: 18),
            Center(child: Column(children: [
              Text('สมัครสมาชิกผู้ป่วย', style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w700, color: const Color(0xff2d6a4f), height: 1.2)),
              const SizedBox(height: 4),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(colors: [Color(0xff1b4332), Color(0xff40916c)]).createShader(b),
                child: Text('เริ่มต้นดูแลสุขภาพของคุณวันนี้', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
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
              _rLabel('ชื่อ-นามสกุล'),
              const SizedBox(height: 8),
              _rField('กรอกชื่อ-นามสกุล', Icons.person_outline_rounded, fullnameCtrl),
              const SizedBox(height: 16),
              _rLabel('อีเมล'),
              const SizedBox(height: 8),
              _rField('กรอกอีเมล', Icons.email_outlined, emailCtrl, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _rLabel('รหัสผ่าน'),
              const SizedBox(height: 8),
              _rPassField('กรอกรหัสผ่าน (อย่างน้อย 6 ตัว)', passCtrl, _obscure, () => setState(() => _obscure = !_obscure)),
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
                        Text('ยืนยันการสมัคร', style: GoogleFonts.notoSansThai(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                          child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
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

  Widget _rLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(text, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w700, fontSize: 13.5, color: const Color(0xff1b4332))),
  );

  Widget _rField(String hint, IconData icon, TextEditingController ctrl, {TextInputType? keyboardType}) => Container(
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

  Widget _rPassField(String hint, TextEditingController ctrl, bool obscure, VoidCallback toggle) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 4))],
    ),
    child: TextField(
      controller: ctrl, obscureText: obscure,
      style: GoogleFonts.notoSansThai(fontSize: 15, color: textDark, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint, hintStyle: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Container(
          margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: const Color(0xffE6F4EA), borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.lock_outline_rounded, color: Color(0xff2d6a4f), size: 18),
        ),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade400, size: 20), onPressed: toggle),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xff74c69d), width: 1.6)),
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    ),
  );
}
