import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/features/auth/register_screen.dart';
import 'package:healthcare_app/features/auth/staff_register_screen.dart';

// ==========================================
// 1. Login Screen
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  bool obscure = true;

  Future<void> login() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
      _snack('กรุณากรอกข้อมูลให้ครบถ้วน');
      return;
    }
    try {
      setState(() => loading = true);
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(), password: passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(e.message ?? 'เกิดข้อผิดพลาด');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xffEEF8F2), Color(0xffFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // รูปตึก
                Image.asset('assets/Log1.1.png', fit: BoxFit.contain, height: 230),
                const SizedBox(height: 1),

                // หัวข้อ
                Center(
                  child: Column(children: [
                    Text('ยินดีต้อนรับสู่',
                      style: GoogleFonts.playfairDisplay(fontSize: 33, fontWeight: FontWeight.w700, color: const Color(0xff2d6a4f), letterSpacing: 0.5, height: 1.2)),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(colors: [Color(0xff1b4332), Color(0xff40916c)]).createShader(b),
                      child: Text('Healthcare Station',
                        style: GoogleFonts.playfairDisplay(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3, height: 1.2)),
                    ),
                    const SizedBox(height: 6),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 30, height: 1.5, color: const Color(0xff40916c).withValues(alpha: 0.4)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.add, color: Color(0xff40916c), size: 16)),
                      Container(width: 30, height: 1.5, color: const Color(0xff40916c).withValues(alpha: 0.4)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 22),

                // อีเมล
                _label('อีเมล'),
                const SizedBox(height: 8),
                _field('กรอกอีเมล', Icons.email_outlined, emailCtrl, false, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 16),

                // รหัสผ่าน
                _label('รหัสผ่าน'),
                const SizedBox(height: 8),
                _field('กรอกรหัสผ่าน', Icons.lock_outline_rounded, passCtrl, true),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
                    child: Text('ลืมรหัสผ่าน?', style: GoogleFonts.notoSansThai(color: const Color(0xff40916c), fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 4),

                // ปุ่มเข้าสู่ระบบ 3D
                GestureDetector(
                  onTap: loading ? null : login,
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xff52b788), Color(0xff2d6a4f), Color(0xff1b4332)],
                      ),
                      boxShadow: [
                        BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 7)),
                        BoxShadow(color: const Color(0xff52b788).withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, -2)),
                      ],
                    ),
                    child: loading
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text('เข้าสู่ระบบ', style: GoogleFonts.notoSansThai(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
                            const SizedBox(width: 14),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                              ),
                              child: const Icon(Icons.eco_rounded, color: Colors.white, size: 18),
                            ),
                          ]),
                  ),
                ),
                const SizedBox(height: 18),

                // สมัครสมาชิก
                Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('ยังไม่มีบัญชี? ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 14)),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: Text('สมัครใช้งาน', style: GoogleFonts.notoSansThai(color: const Color(0xff2d6a4f), fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ])),
                const SizedBox(height: 12),

                // ปุ่มสมัครนักกายภาพ
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffRegisterScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xff40916c).withValues(alpha: 0.45), width: 1.5),
                      color: const Color(0xffF0FAF4),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.medical_services_outlined, color: Color(0xff2d6a4f), size: 20),
                      const SizedBox(width: 10),
                      Text('สมัครบัญชีสำหรับนักกายภาพ', style: GoogleFonts.notoSansThai(color: const Color(0xff2d6a4f), fontWeight: FontWeight.w700, fontSize: 14)),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
    style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xff1b4332)));

  Widget _field(String hint, IconData icon, TextEditingController ctrl, bool isPass, {TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xffF8FEFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffB7E4C7), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: ctrl, keyboardType: keyboardType,
        obscureText: isPass && obscure,
        style: GoogleFonts.notoSansThai(fontSize: 15, color: textDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(icon, color: const Color(0xff74c69d), size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon: isPass
              ? IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade400, size: 20), onPressed: () => setState(() => obscure = !obscure))
              : null,
        ),
      ),
    );
  }
}
