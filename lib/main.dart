import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const HealthcareStation());
}

// ==========================================
// Theme & Colors
// ==========================================
const Color primaryGreen = Color(0xff186B44);
const Color lightGreen = Color(0xffE6F4EA);
const Color bgWhite = Color(0xffF7FCF9);
const Color textDark = Color(0xff2D312F);



class HealthcareStation extends StatelessWidget {
  const HealthcareStation({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Healthcare Station',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th'), Locale('en')],
      locale: const Locale('th'),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bgWhite,
        colorSchemeSeed: primaryGreen,
        textTheme: GoogleFonts.promptTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: textDark, displayColor: textDark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
          iconTheme: IconThemeData(color: primaryGreen),
          titleTextStyle: TextStyle(color: primaryGreen, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ==========================================
// AuthGate — role-based routing
// ==========================================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!authSnap.hasData) return const LoginScreen();

        // อ่าน role จาก Firestore
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(authSnap.data!.uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (userSnap.hasData && userSnap.data!.exists) {
              String role = (userSnap.data!.data() as Map<String, dynamic>)['role'] ?? 'patient';
              if (role == 'staff') return const StaffNavigation();
              if (role == 'admin') return const AdminNavigation();
            }
            return const MainNavigation();
          },
        );
      },
    );
  }
}

// ==========================================
// Machine Status Card (ESP32 → Firestore)
// ==========================================
class MachineStatusCard extends StatelessWidget {
  final String machineId;
  final String machineName;
  const MachineStatusCard({super.key, this.machineId = 'current', this.machineName = 'เครื่องกายภาพบำบัด'});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('machine_status').doc(machineId).snapshots(),
      builder: (context, snap) {
        bool? isActive;
        Timestamp? lastUpdated;
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          isActive = data['is_active'] as bool?;
          lastUpdated = data['last_updated'] as Timestamp?;
        }

        const timeoutSeconds = 30;
        bool isStale = false;
        if (lastUpdated != null) {
          final age = DateTime.now().difference(lastUpdated.toDate());
          if (age.inSeconds >= timeoutSeconds) isStale = true;
        } else if (snap.hasData && snap.data!.exists) {
          isStale = true;
        }

        Color statusColor;
        Color bgColor;
        IconData statusIcon;
        String statusText;
        String statusSub;

        if (snap.connectionState == ConnectionState.waiting) {
          statusColor = Colors.grey;
          bgColor = Colors.grey.shade100;
          statusIcon = Icons.hourglass_empty;
          statusText = 'กำลังตรวจสอบ...';
          statusSub = 'กรุณารอสักครู่';
        } else if (isStale) {
          statusColor = Colors.orange;
          bgColor = Colors.orange.shade50;
          statusIcon = Icons.signal_wifi_statusbar_connected_no_internet_4;
          statusText = 'ไม่ทราบสถานะ';
          statusSub = 'ไม่มีสัญญาณจากเครื่องนานกว่า $timeoutSeconds วินาที';
        } else if (isActive == null) {
          statusColor = Colors.orange;
          bgColor = Colors.orange.shade50;
          statusIcon = Icons.signal_wifi_statusbar_connected_no_internet_4;
          statusText = 'ไม่ทราบสถานะ';
          statusSub = 'ไม่พบข้อมูลจากเครื่อง';
        } else if (isActive) {
          statusColor = primaryGreen;
          bgColor = lightGreen;
          statusIcon = Icons.play_circle_fill;
          statusText = 'เครื่องกำลังทำงาน';
          statusSub = 'อยู่ระหว่างการให้บริการ';
        } else {
          statusColor = Colors.grey.shade600;
          bgColor = Colors.grey.shade100;
          statusIcon = Icons.pause_circle_filled;
          statusText = 'เครื่องว่างอยู่';
          statusSub = 'พร้อมให้บริการ';
        }

        String timeStr = '';
        if (lastUpdated != null) {
          final dt = lastUpdated.toDate();
          timeStr = 'อัปเดต: ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(statusIcon, color: statusColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(machineName, style: TextStyle(fontSize: 11, color: statusColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                    Text(statusText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor)),
                    Text(statusSub, style: TextStyle(fontSize: 12, color: statusColor.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              if (timeStr.isNotEmpty)
                Text(timeStr, style: TextStyle(fontSize: 10, color: statusColor.withValues(alpha: 0.6))),
              const SizedBox(width: 8),
              if (isActive != null)
                _PulsingDot(color: isActive ? Colors.green : Colors.grey),
            ],
          ),
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

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

                // ชื่อผู้ใช้
                _label('ชื่อผู้ใช้'),
                const SizedBox(height: 8),
                _field('กรอกชื่อผู้ใช้', Icons.person_outline_rounded, emailCtrl, false),
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

  Widget _field(String hint, IconData icon, TextEditingController ctrl, bool isPass) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xffF8FEFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffB7E4C7), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: ctrl,
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
        'createdAt': Timestamp.now(),
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
      backgroundColor: const Color(0xffF3FAF6),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Hero header ──
          Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 250,
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff1b4332), Color(0xff2d6a4f), Color(0xff52b788)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(44)),
              ),
              child: Stack(clipBehavior: Clip.none, children: [
                // decorative blurred circles
                Positioned(top: -50, right: -40, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)))),
                Positioned(bottom: -60, left: -50, child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
                Positioned(top: 60, left: 30, child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.25)))),
                Positioned(top: 100, right: 60, child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.3)))),
                SafeArea(bottom: false, child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('เริ่มต้นดูแลสุขภาพ', style: GoogleFonts.notoSansThai(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text('สมัครสมาชิกผู้ป่วย', style: GoogleFonts.playfairDisplay(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, height: 1.15)),
                  ]),
                )),
              ]),
            ),
            // floating logo badge overlapping header/card seam
            Positioned(
              bottom: -38, left: 0, right: 0,
              child: Center(child: Container(
                width: 84, height: 84,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Image.asset('assets/hart.png', fit: BoxFit.contain),
              )),
            ),
          ]),
          const SizedBox(height: 54),
          // ── Form card ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 26, height: 3, decoration: BoxDecoration(color: const Color(0xff52b788), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 6),
                Container(width: 26, height: 3, decoration: BoxDecoration(color: const Color(0xffB7E4C7), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 6),
                Container(width: 26, height: 3, decoration: BoxDecoration(color: const Color(0xffB7E4C7), borderRadius: BorderRadius.circular(4))),
              ]),
              const SizedBox(height: 24),
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
          ),
        ]),
      ),
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
      DocumentSnapshot inviteDoc = await FirebaseFirestore.instance.collection('settings').doc('staff_invite').get();
      if (!inviteDoc.exists) { _snack('ระบบ Invite Code ยังไม่ได้ตั้งค่า กรุณาติดต่อผู้ดูแลระบบ'); return; }
      String correctCode = (inviteDoc.data() as Map<String, dynamic>)['invite_code'] ?? '';
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
        'createdAt': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สมัครบัญชีนักกายภาพสำเร็จ!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(e.message ?? 'เกิดข้อผิดพลาด');
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
      backgroundColor: const Color(0xffF3FAF6),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Hero header ──
          Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 250,
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xff1b4332), Color(0xff2d6a4f), Color(0xff52b788)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(44)),
              ),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(top: -50, right: -40, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)))),
                Positioned(bottom: -60, left: -50, child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
                Positioned(top: 60, left: 30, child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.25)))),
                Positioned(top: 100, right: 60, child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.3)))),
                SafeArea(bottom: false, child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Text('สำหรับนักกายภาพบำบัด', style: GoogleFonts.notoSansThai(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.5)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                        child: Text('STAFF', style: GoogleFonts.prompt(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text('สมัครบัญชีเจ้าหน้าที่', style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, height: 1.15)),
                  ]),
                )),
              ]),
            ),
            Positioned(
              bottom: -38, left: 0, right: 0,
              child: Center(child: Container(
                width: 84, height: 84,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xff1b4332).withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.medical_services_rounded, color: Color(0xff2d6a4f), size: 32),
              )),
            ),
          ]),
          const SizedBox(height: 54),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 26, height: 3, decoration: BoxDecoration(color: const Color(0xff52b788), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 6),
                Container(width: 26, height: 3, decoration: BoxDecoration(color: const Color(0xffB7E4C7), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 6),
                Container(width: 26, height: 3, decoration: BoxDecoration(color: const Color(0xffB7E4C7), borderRadius: BorderRadius.circular(4))),
              ]),
              const SizedBox(height: 24),
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
          ),
        ]),
      ),
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

// ==========================================
// 4. Main Navigation (Patient)
// ==========================================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int index = 0;
  final pages = [const HomeScreen(), const ActiveQueueScreen(), const HistoryScreen(), const ProfileScreen()];

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

// ==========================================
// 5. Home Screen (Patient) + MachineStatusCard
// ==========================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xffF5FAF6),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
        builder: (context, snap) {
          String name = 'ผู้ใช้งาน';
          String photoBase64 = '';
          if (snap.hasData && snap.data!.exists) {
            final d = snap.data!.data() as Map<String, dynamic>;
            name = d['fullname'] ?? 'ผู้ใช้งาน';
            photoBase64 = d['photoBase64'] ?? '';
          }
          ImageProvider? photo;
          if (photoBase64.isNotEmpty) { try { photo = MemoryImage(base64Decode(photoBase64)); } catch (_) {} }

          return SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // ===== Header =====
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(children: [
                    // Logo
                    Row(children: [
                      Image.asset('assets/hart.png', width: 44, height: 44),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Healthcare', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold, color: primaryGreen)),
                        Text('Station', style: GoogleFonts.playfairDisplay(fontSize: 14, fontWeight: FontWeight.bold, color: primaryGreen)),
                      ]),
                    ]),
                    const Spacer(),
                    // Greeting
                    Row(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('สวัสดี, ${name.split(' ').first}', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w600, color: textDark)),
                      ]),
                      const SizedBox(width: 6),
                      const Text('👋', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      CircleAvatar(
                        radius: 18, backgroundColor: lightGreen,
                        backgroundImage: photo,
                        child: photo == null ? const Icon(Icons.person, color: primaryGreen, size: 20) : null,
                      ),
                    ]),
                  ]),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ===== Queue Card =====
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('appointments').where('patientUid', isEqualTo: user?.uid).snapshots(),
                      builder: (context, snap) {
                        String qNo = ''; String status = ''; String? activeDocId;
                        String time = '';
                        if (snap.hasData && snap.data!.docs.isNotEmpty) {
                          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
                          var latest = docs.first;
                          if (!['เสร็จสิ้น', 'ยกเลิก'].contains(latest['status'])) {
                            qNo = latest['queueNo'] ?? '';
                            status = latest['status'] ?? '';
                            activeDocId = latest.id;
                            time = latest['time'] ?? '';
                          }
                        }
                        final bool hasQueue = qNo.isNotEmpty;
                        Color statusColor = status == 'กำลังรักษา' ? Colors.orange.shade700 : status == 'เรียกคิว' ? Colors.blue.shade700 : primaryGreen;

                        return Container(
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: hasQueue
                            ? Stack(children: [
                                // Hospital image right side
                                Positioned(right: 0, top: 0, bottom: 0, width: 160,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                                    child: Stack(fit: StackFit.expand, children: [
                                      Image.asset('assets/Log1.1.png', fit: BoxFit.cover),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.white, Colors.white.withValues(alpha: 0)]),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                                // Content left side
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 20, 170, 20),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('คิวของคุณวันนี้', style: GoogleFonts.notoSansThai(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(qNo, style: GoogleFonts.prompt(fontSize: 52, fontWeight: FontWeight.bold, color: primaryGreen, height: 1.1)),
                                    const SizedBox(height: 12),
                                    // Status pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                        borderRadius: BorderRadius.circular(30),
                                        color: statusColor.withValues(alpha: 0.06),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.access_time_rounded, size: 14, color: statusColor),
                                        const SizedBox(width: 6),
                                        Text(status, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
                                      ]),
                                    ),
                                    const SizedBox(height: 12),
                                    if (time.isNotEmpty)
                                      Row(children: [
                                        Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                                        const SizedBox(width: 6),
                                        Text('นัดเวลา $time', style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 12)),
                                      ]),
                                    if (activeDocId != null && status == 'กำลังรอ') ...[
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: () => _confirmCancel(context, activeDocId!),
                                        child: Text('ยกเลิกคิว', style: GoogleFonts.notoSansThai(color: Colors.red.shade400, fontSize: 12, decoration: TextDecoration.underline)),
                                      ),
                                    ],
                                  ]),
                                ),
                              ])
                            : Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(children: [
                                  Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.calendar_month_rounded, color: primaryGreen, size: 28)),
                                  const SizedBox(width: 16),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('ยังไม่มีคิว', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
                                    const SizedBox(height: 4),
                                    Text('กดจองคิวเพื่อพบนักกายภาพบำบัด', style: GoogleFonts.notoSansThai(color: Colors.grey, fontSize: 12)),
                                  ])),
                                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
                                ]),
                              ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // ===== Action Cards =====
                    Row(children: [
                      Expanded(child: _actionCard(context, Icons.calendar_month_rounded, 'จองคิวใหม่', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingScreen())))),
                      const SizedBox(width: 14),
                      Expanded(child: _actionCard(context, Icons.format_list_bulleted_rounded, 'ประวัติการรักษา', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())))),
                    ]),
                    const SizedBox(height: 22),

                    // ===== Services =====
                    Text('บริการของเรา', style: GoogleFonts.notoSansThai(fontSize: 15, fontWeight: FontWeight.bold, color: primaryGreen)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _serviceCard(context, 'กายภาพบำบัด', Icons.accessibility_new_rounded, false, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingScreen())))),
                      const SizedBox(width: 12),
                      Expanded(child: _serviceCard(context, 'แจ้งเตือน', Icons.notifications_rounded, false, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())))),
                      const SizedBox(width: 12),
                      Expanded(child: _serviceCard(context, 'แจ้งเหตุฉุกเฉิน', Icons.sos_rounded, true, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SOSScreen())))),
                    ]),
                    const SizedBox(height: 20),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmCancel(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 10), Text('ยืนยันการยกเลิกคิว', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        content: const Text('คุณต้องการยกเลิกคิวนี้ใช่หรือไม่?\nไม่สามารถนำคิวกลับคืนได้', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ไม่ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('appointments').doc(docId).update({'status': 'ยกเลิก', 'cancelledAt': Timestamp.now()});
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคิวเรียบร้อยแล้ว'), backgroundColor: Colors.red));
            },
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(BuildContext ctx, IconData icon, String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: primaryGreen.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
            const BoxShadow(color: Colors.white, blurRadius: 0, offset: Offset(0, 0)),
          ],
        ),
        child: Column(children: [
          _icon3D(icon, [const Color(0xff1b4332), const Color(0xff52b788)], 60),
          const SizedBox(height: 14),
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, color: textDark, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xff1b4332), Color(0xff52b788)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
          ),
        ]),
      ),
    );
  }

  Widget _serviceCard(BuildContext ctx, String title, IconData icon, bool isSOS, VoidCallback onTap) {
    final List<Color> iconColors = isSOS
        ? [Colors.red.shade300, Colors.red.shade700]
        : [const Color(0xff52b788), const Color(0xff186B44)];
    final List<Color> arrowColors = isSOS
        ? [Colors.red.shade400, Colors.red.shade700]
        : [const Color(0xff52b788), const Color(0xff1b4332)];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Column(children: [
          _icon3D(icon, iconColors, 58),
          const SizedBox(height: 10),
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, fontSize: 11, color: textDark), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: arrowColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [BoxShadow(color: arrowColors[1].withValues(alpha: 0.4), blurRadius: 5, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white),
          ),
        ]),
      ),
    );
  }

  Widget _icon3D(IconData icon, List<Color> colors, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(color: colors[1].withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 6)),
          BoxShadow(color: colors[0].withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(-2, -2)),
        ],
      ),
      child: Stack(children: [
        // shine highlight top-left
        Positioned(top: 6, left: 6, child: Container(
          width: size * 0.45, height: size * 0.2,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(size),
          ),
        )),
        Center(child: Icon(icon, size: size * 0.5, color: Colors.white)),
      ]),
    );
  }
}

// ==========================================
// 6. Booking Screen
// ==========================================
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int selectedDateIndex = 0;
  int selectedStaffIndex = 0;
  int selectedTimeIndex = 0;
  bool isSubmitting = false;
  List<String> availableTimes = [];
  bool loadingTimes = false;
  List<Map<String, dynamic>> staffList = [];
  bool loadingStaff = false;
  String? selectedMachineId;
  String selectedMachineName = '';

  late List<DateTime> upcomingDays;
  final List<String> thaiDayNames = ['', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

  @override
  void initState() {
    super.initState();
    DateTime today = DateTime.now();
    upcomingDays = List.generate(7, (i) => today.add(Duration(days: i)));
    for (int i = 0; i < upcomingDays.length; i++) {
      if (upcomingDays[i].weekday != DateTime.saturday && upcomingDays[i].weekday != DateTime.sunday) {
        selectedDateIndex = i; break;
      }
    }
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => loadingStaff = true);
    try {
      var snap = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').get();
      if (mounted) setState(() { staffList = snap.docs.map((d) => d.data()).toList(); loadingStaff = false; });
    } catch (_) {
      if (mounted) setState(() => loadingStaff = false);
    }
    _loadAvailability();
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';

  Future<void> _loadAvailability() async {
    if (!mounted) return;
    setState(() => loadingTimes = true);
    String dateStr = _fmt(upcomingDays[selectedDateIndex]);
    try {
      String staffUid = staffList.isNotEmpty ? (staffList[selectedStaffIndex]['uid'] ?? '') : '';
      String docId = '${staffUid}_$dateStr';
      var docSnap = await FirebaseFirestore.instance.collection('staff_availability').doc(docId).get();
      List<String> times = [];
      if (docSnap.exists) {
        final raw = docSnap.data()?['times'];
        if (raw is List && raw.isNotEmpty) times = List<String>.from(raw);
      }
      var apptSnap = await FirebaseFirestore.instance.collection('appointments').where('date', isEqualTo: dateStr).where('staffUid', isEqualTo: staffList.isNotEmpty ? (staffList[selectedStaffIndex]['uid'] ?? '') : '').where('status', whereIn: ['กำลังรอ', 'เรียกคิว', 'กำลังรักษา']).get();
      Set<String> bookedTimes = {};
      for (var doc in apptSnap.docs) {
        String t = (doc.data())['time'] ?? '';
        if (t.isNotEmpty) bookedTimes.add(t);
      }
      List<String> freeTimes = times.where((t) => !bookedTimes.contains(t)).toList();
      if (mounted) setState(() { availableTimes = freeTimes; selectedTimeIndex = 0; loadingTimes = false; });
    } catch (_) {
      if (mounted) setState(() { availableTimes = []; loadingTimes = false; });
    }
  }

  Future<void> submitBooking() async {
    try {
      setState(() => isSubmitting = true);
      User? user = FirebaseAuth.instance.currentUser;
      var existing = await FirebaseFirestore.instance.collection('appointments').where('patientUid', isEqualTo: user!.uid).where('status', whereIn: ['กำลังรอ', 'เรียกคิว', 'กำลังรักษา']).get();
      if (existing.docs.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณมีคิวที่ยังไม่เสร็จสิ้นอยู่แล้ว'), backgroundColor: Colors.orange));
        return;
      }
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      String patientName = userDoc.data()?['fullname'] ?? 'ผู้ป่วยไม่ทราบชื่อ';
      String dateStr = _fmt(upcomingDays[selectedDateIndex]);
      // นับคิวในวันนั้นเพื่อให้เป็นลำดับ
      var todayAppts = await FirebaseFirestore.instance.collection('appointments').where('date', isEqualTo: dateStr).get();
      int nextNum = todayAppts.docs.length + 1;
      String qNo = nextNum.toString().padLeft(3, '0');
      await FirebaseFirestore.instance.collection('appointments').add({
        'patientUid': user.uid, 'patientName': patientName, 'queueNo': qNo,
        'doctor': staffList.isNotEmpty ? (staffList[selectedStaffIndex]['fullname'] ?? 'นักกายภาพ') : 'นักกายภาพ',
        'staffUid': staffList.isNotEmpty ? (staffList[selectedStaffIndex]['uid'] ?? '') : '',
        'date': _fmt(upcomingDays[selectedDateIndex]), 'time': availableTimes[selectedTimeIndex],
        'status': 'กำลังรอ', 'notes': '', 'machineId': selectedMachineId ?? '', 'machineName': selectedMachineName, 'createdAt': Timestamp.now(),
      });
      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainNavigation()), (r) => false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('จองคิวสำเร็จ!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffEDF7F1),
      body: Column(children: [
        // ===== Header =====
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: primaryGreen, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Text('จองคิวใหม่', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
            const Spacer(),
            Image.asset('assets/hart.png', width: 36, height: 36),
          ]),
        ),

        // ===== Body =====
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Step 1: วันที่ ──
            _bookingCard(
              step: 1, icon: Icons.calendar_month_rounded, title: 'เลือกวันที่นัดหมาย',
              child: SizedBox(
                height: 82,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal, itemCount: upcomingDays.length,
                  itemBuilder: (_, i) {
                    DateTime date = upcomingDays[i];
                    bool isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
                    bool isSel = i == selectedDateIndex && !isWeekend;
                    return GestureDetector(
                      onTap: isWeekend ? null : () { setState(() => selectedDateIndex = i); _loadAvailability(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 58, margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          gradient: isSel ? const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                          color: isWeekend ? Colors.grey.shade100 : (isSel ? null : lightGreen),
                          borderRadius: BorderRadius.circular(16),
                          border: isSel ? null : Border.all(color: isWeekend ? Colors.grey.shade200 : primaryGreen.withValues(alpha: 0.15)),
                          boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : [],
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(thaiDayNames[date.weekday], style: GoogleFonts.notoSansThai(fontSize: 11, fontWeight: FontWeight.bold, color: isWeekend ? Colors.grey.shade400 : (isSel ? Colors.white70 : primaryGreen.withValues(alpha: 0.7)))),
                          const SizedBox(height: 2),
                          Text('${date.day}', style: GoogleFonts.prompt(fontSize: 22, fontWeight: FontWeight.bold, color: isWeekend ? Colors.grey.shade400 : (isSel ? Colors.white : textDark))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Step 2: นักกายภาพ ──
            _bookingCard(
              step: 2, icon: Icons.person_rounded, title: 'เลือกนักกายภาพ',
              child: loadingStaff
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: primaryGreen)))
                : staffList.isEmpty
                  ? _infoBox('ยังไม่มีนักกายภาพในระบบ', Colors.orange)
                  : Column(children: List.generate(staffList.length, (i) {
                      bool isSel = i == selectedStaffIndex;
                      final photo = staffList[i]['photoBase64'] ?? '';
                      ImageProvider? photoImg;
                      if (photo.isNotEmpty) { try { photoImg = MemoryImage(base64Decode(photo)); } catch (_) {} }
                      return GestureDetector(
                        onTap: () { setState(() { selectedStaffIndex = i; selectedTimeIndex = 0; }); _loadAvailability(); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSel ? lightGreen : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSel ? primaryGreen : Colors.grey.shade200, width: isSel ? 1.5 : 1),
                          ),
                          child: Row(children: [
                            Stack(children: [
                              CircleAvatar(radius: 26, backgroundColor: lightGreen, backgroundImage: photoImg, child: photoImg == null ? const Icon(Icons.person_rounded, color: primaryGreen, size: 24) : null),
                              if (isSel) Positioned(bottom: 0, right: 0, child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(color: primaryGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                child: const Icon(Icons.check, color: Colors.white, size: 9),
                              )),
                            ]),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(staffList[i]['fullname'] ?? 'นักกายภาพ', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                              Text('นักกายภาพบำบัด', style: GoogleFonts.notoSansThai(fontSize: 12, color: Colors.grey.shade500)),
                            ])),
                            if (isSel) Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: primaryGreen, borderRadius: BorderRadius.circular(20)),
                              child: Text('เลือกแล้ว', style: GoogleFonts.notoSansThai(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ]),
                        ),
                      );
                    })),
            ),
            const SizedBox(height: 14),

            // ── Step 3: เครื่อง ──
            _bookingCard(
              step: 3, icon: Icons.computer_rounded, title: 'เลือกเครื่องที่ใช้',
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('machine_status').snapshots(),
                builder: (context, machineSnap) {
                  if (!machineSnap.hasData || machineSnap.data!.docs.isEmpty) {
                    return _infoBox('ไม่พบข้อมูลเครื่อง', Colors.grey);
                  }
                  return Column(children: machineSnap.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final bool? isActive = data['is_active'] as bool?;
                    final Timestamp? lastUpd = data['last_updated'] as Timestamp?;
                    final String name = data['name'] ?? doc.id;
                    bool stale = false;
                    if (lastUpd != null) { stale = DateTime.now().difference(lastUpd.toDate()).inSeconds >= 30; }
                    else if (data.containsKey('is_active')) { stale = true; }
                    Color sColor; String sText; IconData sIcon;
                    if (stale || isActive == null) { sColor = Colors.orange; sText = 'ไม่ทราบสถานะ'; sIcon = Icons.help_outline_rounded; }
                    else if (isActive) { sColor = primaryGreen; sText = 'กำลังทำงาน'; sIcon = Icons.play_circle_rounded; }
                    else { sColor = Colors.grey; sText = 'ว่างอยู่'; sIcon = Icons.pause_circle_rounded; }
                    bool isSel = selectedMachineId == doc.id;
                    return GestureDetector(
                      onTap: () => setState(() { selectedMachineId = doc.id; selectedMachineName = name; }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSel ? sColor.withValues(alpha: 0.07) : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSel ? sColor : Colors.grey.shade200, width: isSel ? 1.5 : 1),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: sColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(sIcon, color: sColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: sColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text(sText, style: GoogleFonts.notoSansThai(fontSize: 11, color: sColor, fontWeight: FontWeight.w600)),
                            ),
                          ])),
                          if (isSel) Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: sColor, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                          ),
                        ]),
                      ),
                    );
                  }).toList());
                },
              ),
            ),
            const SizedBox(height: 14),

            // ── Step 4: เวลา ──
            _bookingCard(
              step: 4, icon: Icons.access_time_rounded, title: 'เลือกเวลา',
              child: loadingTimes
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: primaryGreen)))
                : availableTimes.isEmpty
                  ? _infoBox('ไม่มีช่วงเวลาที่เปิดในวันนี้', Colors.orange)
                  : GridView.builder(
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.0, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: availableTimes.length,
                      itemBuilder: (_, i) {
                        bool isSel = i == selectedTimeIndex;
                        String time = availableTimes[i];
                        return GestureDetector(
                          onTap: () => setState(() => selectedTimeIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              gradient: isSel ? const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                              color: isSel ? null : lightGreen,
                              borderRadius: BorderRadius.circular(12),
                              border: isSel ? null : Border.all(color: primaryGreen.withValues(alpha: 0.2)),
                              boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))] : [],
                            ),
                            child: Center(child: Text(time, style: GoogleFonts.prompt(fontWeight: FontWeight.bold, fontSize: 15, color: isSel ? Colors.white : primaryGreen))),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 24),

            // ── ปุ่มยืนยัน ──
            if (staffList.isNotEmpty && availableTimes.isNotEmpty && selectedMachineId != null)
              Container(
                width: double.infinity, height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  onPressed: isSubmitting ? null : submitBooking,
                  child: isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text('ยืนยันการจองคิว', style: GoogleFonts.notoSansThai(fontSize: 17, color: Colors.white, fontWeight: FontWeight.bold)),
                      ]),
                ),
              ),
          ]),
        )),
      ]),
    );
  }

  Widget _bookingCard({required int step, required IconData icon, required String title, required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text('$step', style: GoogleFonts.prompt(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: primaryGreen, size: 18),
        const SizedBox(width: 6),
        Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
      ]),
      const SizedBox(height: 14),
      child,
    ])),
  );


  Widget _infoBox(String msg, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Row(children: [
      Icon(Icons.info_outline_rounded, color: color, size: 20),
      const SizedBox(width: 10),
      Text(msg, style: GoogleFonts.notoSansThai(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );

}

// ==========================================
// 7. Active Queue Screen
// ==========================================
class ActiveQueueScreen extends StatelessWidget {
  const ActiveQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xffF5FAF6),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('appointments').where('patientUid', isEqualTo: user?.uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
          if (!snap.hasData || snap.data!.docs.isEmpty) return _empty('คุณยังไม่มีคิวในขณะนี้');
          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
          var latest = docs.first;
          var data = latest.data() as Map<String, dynamic>;
          if (data['status'] == 'เสร็จสิ้น') return _empty('คิวของคุณเสร็จสิ้นแล้ว');
          if (data['status'] == 'ยกเลิก') return _cancelled();
          String status = data['status'] ?? 'กำลังรอ';
          bool isWait = status == 'กำลังรอ', isCall = status == 'เรียกคิว', isTreat = status == 'กำลังรักษา';
          Color statusColor = isTreat ? Colors.orange.shade700 : isCall ? Colors.blue.shade700 : primaryGreen;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // ===== Header =====
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                child: Row(children: [
                  Image.asset('assets/hart.png', width: 40, height: 40),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Healthcare', style: GoogleFonts.playfairDisplay(fontSize: 13, fontWeight: FontWeight.bold, color: primaryGreen)),
                    Text('Station', style: GoogleFonts.playfairDisplay(fontSize: 13, fontWeight: FontWeight.bold, color: primaryGreen)),
                  ]),
                  const Spacer(),
                  Text('คิวของฉัน', style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.bold, color: textDark)),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(children: [

                  // ===== Queue Card (same style as HomeScreen) =====
                  Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                    ),
                    child: Stack(children: [
                      Positioned(right: 0, top: 0, bottom: 0, width: 155,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.asset('assets/Log1.1.png', fit: BoxFit.cover),
                            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.white, Colors.white.withValues(alpha: 0)]))),
                          ]),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 165, 20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('คิวของคุณวันนี้', style: GoogleFonts.notoSansThai(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(data['queueNo'] ?? '-', style: GoogleFonts.prompt(fontSize: 52, fontWeight: FontWeight.bold, color: primaryGreen, height: 1.1)),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(border: Border.all(color: statusColor.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(30), color: statusColor.withValues(alpha: 0.06)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.access_time_rounded, size: 14, color: statusColor),
                              const SizedBox(width: 6),
                              Text(status, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          if ((data['time'] ?? '').isNotEmpty)
                            Row(children: [Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6), Text('นัดเวลา ${data['time']}', style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 12))]),
                          const SizedBox(height: 4),
                          if ((data['doctor'] ?? '').isNotEmpty)
                            Row(children: [Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6), Expanded(child: Text(data['doctor'], style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 12), overflow: TextOverflow.ellipsis))]),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Cancel button
                  if (isWait)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300), foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: Text('ยกเลิกคิว', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15)),
                        onPressed: () => _confirmCancel(context, latest.id),
                      ),
                    ),
                  if (isWait) const SizedBox(height: 16),

                  // ===== Progress Steps =====
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ขั้นตอนการรับบริการ', style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.bold, color: primaryGreen)),
                      const SizedBox(height: 20),
                      _step(Icons.check_circle_rounded, 'ลงทะเบียนสำเร็จ', 'บันทึกข้อมูลเรียบร้อย', true, isLast: false),
                      _step(Icons.favorite_rounded, 'รอพบนักกายภาพบำบัด', 'กรุณารอเจ้าหน้าที่เรียกคิว', isWait || isCall || isTreat, isActive: isWait, isLast: false),
                      _step(Icons.campaign_rounded, 'เรียกคิว', 'เชิญที่ห้องตรวจ', isCall || isTreat, isActive: isCall, isLast: false),
                      _step(Icons.medical_services_rounded, 'เข้ารับการรักษา', 'พบนักกายภาพบำบัดตามคิว', isTreat, isActive: isTreat, isLast: true),
                    ]),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmCancel(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 10), Text('ยืนยันการยกเลิกคิว', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        content: const Text('คุณต้องการยกเลิกคิวนี้ใช่หรือไม่?\nไม่สามารถนำคิวกลับคืนได้', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ไม่ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('appointments').doc(docId).update({'status': 'ยกเลิก', 'cancelledAt': Timestamp.now()});
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคิวเรียบร้อยแล้ว'), backgroundColor: Colors.red));
            },
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
  }

  Widget _empty(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: lightGreen, shape: BoxShape.circle), child: const Icon(Icons.event_busy_rounded, size: 56, color: primaryGreen)),
    const SizedBox(height: 16),
    Text(msg, style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w500)),
    const SizedBox(height: 8),
    Text('กดแท็บ "หน้าแรก" เพื่อจองคิว', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 13)),
  ]));

  Widget _cancelled() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.cancel_rounded, size: 60, color: Colors.red)),
    const SizedBox(height: 16),
    Text('คิวถูกยกเลิกแล้ว', style: GoogleFonts.notoSansThai(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
    const SizedBox(height: 8),
    Text('สามารถจองคิวใหม่ได้เลย', style: GoogleFonts.notoSansThai(color: Colors.grey, fontSize: 14)),
  ]));

  Widget _step(IconData icon, String title, String sub, bool done, {bool isActive = false, required bool isLast}) {
    Color color = isActive ? Colors.orange.shade600 : (done ? primaryGreen : Colors.grey.shade300);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: done || isActive ? LinearGradient(colors: isActive ? [Colors.orange.shade300, Colors.orange.shade700] : [const Color(0xff52b788), const Color(0xff1b4332)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            color: done || isActive ? null : Colors.grey.shade200,
            shape: BoxShape.circle,
            boxShadow: done || isActive ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 4))] : [],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        if (!isLast) Container(width: 2, height: 36, margin: const EdgeInsets.symmetric(vertical: 4), decoration: BoxDecoration(gradient: done ? const LinearGradient(colors: [Color(0xff52b788), Color(0xff1b4332)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null, color: done ? null : Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
      ]),
      const SizedBox(width: 16),
      Expanded(child: Padding(
        padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: done || isActive ? textDark : Colors.grey.shade400)),
          const SizedBox(height: 3),
          Text(sub, style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)),
        ]),
      )),
      if (done && !isActive) const Icon(Icons.check_circle_rounded, color: primaryGreen, size: 20),
    ]);
  }
}

// ==========================================
// 8. History Screen (Patient) — เลือกวันได้
// ==========================================
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Color _statusColor(String s) {
    switch (s) {
      case 'เสร็จสิ้น': return Colors.green;
      case 'กำลังรักษา': return Colors.blue;
      case 'เรียกคิว': return Colors.deepOrange;
      case 'ยกเลิก': return Colors.red;
      default: return Colors.orange;
    }
  }

  void _showDetail(BuildContext ctx, Map<String, dynamic> data) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.medical_services, color: primaryGreen), const SizedBox(width: 10), Text('คิว ${data['queueNo'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold))]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.local_hospital, 'นักกายภาพ', data['doctor'] ?? '-'),
          _row(Icons.calendar_today, 'วันที่', data['date'] ?? '-'),
          _row(Icons.access_time, 'เวลา', data['time'] ?? '-'),
          _row(Icons.computer_rounded, 'เครื่อง', (data['machineName'] ?? '').toString().isNotEmpty ? data['machineName'] : '-'),
          _row(Icons.info_outline, 'สถานะ', data['status'] ?? '-'),
          if ((data['notes'] ?? '').toString().isNotEmpty) _row(Icons.note_alt_outlined, 'บันทึกจากเจ้าหน้าที่', data['notes']),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด', style: TextStyle(color: primaryGreen)))],
      ),
    );
  }

  Widget _row(IconData icon, String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: primaryGreen), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w600, color: textDark)),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติการรักษา')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('appointments').where('patientUid', isEqualTo: user?.uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('ยังไม่มีประวัติ', style: TextStyle(color: Colors.grey)));
          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
          return ListView.builder(
            padding: const EdgeInsets.all(16), itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              String status = data['status'] ?? 'กำลังรอ';
              Color sc = _statusColor(status);
              bool isCancelled = status == 'ยกเลิก';
              return GestureDetector(
                onTap: () => _showDetail(context, data),
                child: Opacity(
                  opacity: isCancelled ? 0.6 : 1.0,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
                      border: Border(left: BorderSide(color: sc, width: 4)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.medical_services, color: sc, size: 18)),
                            const SizedBox(width: 10),
                            Text('คิว ${data['queueNo'] ?? '-'}', style: GoogleFonts.prompt(fontWeight: FontWeight.bold, fontSize: 17, color: textDark)),
                          ]),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text(status, style: GoogleFonts.notoSansThai(color: sc, fontWeight: FontWeight.bold, fontSize: 11))),
                        ]),
                        const SizedBox(height: 8),
                        Text(data['doctor'] ?? '-', style: GoogleFonts.notoSansThai(color: textDark, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.calendar_today, size: 13, color: Colors.grey), const SizedBox(width: 4),
                          Text(data['date'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(width: 12),
                          const Icon(Icons.access_time, size: 13, color: Colors.grey), const SizedBox(width: 4),
                          Text(data['time'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          if ((data['machineName'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(width: 12),
                            const Icon(Icons.computer_rounded, size: 13, color: Colors.grey), const SizedBox(width: 4),
                            Expanded(child: Text(data['machineName'], style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
                          ],
                        ]),
                        if ((data['notes'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(8)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.note_alt_outlined, size: 14, color: primaryGreen), const SizedBox(width: 6), Expanded(child: Text(data['notes'], style: const TextStyle(fontSize: 12, color: primaryGreen)))])),
                        ],
                      ]),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

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
      final base64Str = base64Encode(bytes);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'photoBase64': base64Str});
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดไม่สำเร็จ: $e'), backgroundColor: Colors.red));
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
        future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
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
          ImageProvider? photoImage;
          if (photoBase64.isNotEmpty) {
            try { photoImage = MemoryImage(base64Decode(photoBase64)); } catch (_) {}
          }

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

// ==========================================
// 10. Notification Screen
// ==========================================
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน')),
      body: const Center(child: Text('ฟีเจอร์แจ้งเตือนจะมาในเร็วๆ นี้', style: TextStyle(color: Colors.grey))),
    );
  }
}

// ==========================================
// 11. SOS Screen
// ==========================================
class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  String selectedIssue = 'ผู้ป่วยหมดสติ';
  final otherCtrl = TextEditingController();
  final issues = ['ผู้ป่วยหมดสติ', 'หกล้มบาดเจ็บรุนแรง', 'หายใจไม่ออก / แน่นหน้าอก', 'อื่นๆ'];
  bool isSending = false;

  Future<void> sendSOS() async {
    String message = selectedIssue == 'อื่นๆ' ? otherCtrl.text : selectedIssue;
    if (message.isEmpty) return;
    setState(() => isSending = true);
    User? user = FirebaseAuth.instance.currentUser;
    try {
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      String patientName = userDoc.data()?['fullname'] ?? 'ผู้ป่วยไม่ทราบชื่อ';
      await FirebaseFirestore.instance.collection('sos_alerts').add({'patientUid': user.uid, 'patientName': patientName, 'issue': message, 'status': 'รอรับเรื่อง', 'createdAt': Timestamp.now()});
      if (mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 50),
            title: const Text('ส่งสัญญาณ SOS สำเร็จ'),
            content: Text('เจ้าหน้าที่ได้รับแจ้งเหตุ:\n\'$message\'\nและกำลังตรวจสอบ กรุณารอสักครู่', textAlign: TextAlign.center),
            actions: [SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white), onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text('ตกลง')))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แจ้งเหตุฉุกเฉิน', style: TextStyle(color: Colors.red)), iconTheme: const IconThemeData(color: Colors.red)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 80))),
          const SizedBox(height: 30),
          const Text('ระบุอาการหรือเหตุฉุกเฉิน:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          RadioGroup<String>(
            groupValue: selectedIssue,
            onChanged: (v) { if (v != null) setState(() => selectedIssue = v); },
            child: Column(children: issues.map((issue) => RadioListTile<String>(value: issue, title: Text(issue, style: const TextStyle(fontWeight: FontWeight.w500)), contentPadding: EdgeInsets.zero)).toList()),
          ),
          if (selectedIssue == 'อื่นๆ') ...[
            const SizedBox(height: 10),
            TextField(controller: otherCtrl, maxLines: 3, decoration: InputDecoration(hintText: 'โปรดระบุรายละเอียด...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
          ],
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            icon: const Icon(Icons.sos, size: 30),
            label: isSending ? const CircularProgressIndicator(color: Colors.white) : const Text('ส่งสัญญาณขอความช่วยเหลือ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            onPressed: isSending ? null : sendSOS,
          )),
        ]),
      ),
    );
  }
}

// =======================================================================================
// STAFF SECTION
// =======================================================================================

class StaffNavigation extends StatefulWidget {
  const StaffNavigation({super.key});
  @override
  State<StaffNavigation> createState() => _StaffNavigationState();
}

class _StaffNavigationState extends State<StaffNavigation> {
  int index = 0;
  final pages = [const StaffQueueScreen(), const StaffSOSScreen(), const StaffTreatmentHistoryScreen(), const StaffAvailabilityScreen(), const ProfileScreen()];

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

// Staff: Queue Management + MachineStatusCard
class StaffQueueScreen extends StatelessWidget {
  const StaffQueueScreen({super.key});

  Future<void> _update(String docId, String status, {String notes = ''}) async {
    Map<String, dynamic> data = {'status': status};
    if (status == 'เสร็จสิ้น') { data['completedAt'] = Timestamp.now(); if (notes.isNotEmpty) data['notes'] = notes; }
    await FirebaseFirestore.instance.collection('appointments').doc(docId).update(data);
  }

  void _completeDialog(BuildContext ctx, String docId) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('บันทึกผลการรักษา', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('บันทึกเพิ่มเติม (ไม่บังคับ):', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(controller: notesCtrl, maxLines: 3, decoration: InputDecoration(hintText: 'เช่น ให้ยา / คำแนะนำ / นัดหมายครั้งถัดไป...', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: () { Navigator.pop(ctx); _update(docId, 'เสร็จสิ้น', notes: notesCtrl.text.trim()); }, child: const Text('ยืนยันเสร็จสิ้น')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('appointments').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
          var docs = (snap.data?.docs ?? []).where((d) => !['เสร็จสิ้น', 'ยกเลิก'].contains(d['status'])).toList()
            ..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return ta.compareTo(tb); });
          int waiting = docs.where((d) => d['status'] == 'กำลังรอ').length;
          int calling = docs.where((d) => d['status'] == 'เรียกคิว').length;
          int treating = docs.where((d) => d['status'] == 'กำลังรักษา').length;

          return Column(children: [
            // ── Header ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Image.asset('assets/hart.png', width: 36),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('จัดการคิวผู้ป่วย', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                    Text('ติดตามสถานะแบบเรียลไทม์', style: GoogleFonts.notoSansThai(fontSize: 11, color: Colors.grey.shade400)),
                  ]),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Text('${docs.length} คิว', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  _qStatBlock('กำลังรอ', waiting, primaryGreen, Icons.access_time_rounded),
                  const SizedBox(width: 10),
                  _qStatBlock('เรียกแล้ว', calling, Colors.blue.shade600, Icons.campaign_rounded),
                  const SizedBox(width: 10),
                  _qStatBlock('กำลังรักษา', treating, Colors.orange.shade700, Icons.medical_services_rounded),
                ]),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: docs.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: lightGreen, shape: BoxShape.circle), child: Image.asset('assets/hart.png', width: 52)),
                    const SizedBox(height: 18),
                    Text('ไม่มีคิวค้างอยู่ในขณะนี้', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('ผู้ป่วยทุกคนได้รับการดูแลแล้ว', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 13)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      var doc = docs[i]; var data = doc.data() as Map<String, dynamic>;
                      String status = data['status'] ?? 'กำลังรอ';
                      Color statusColor; IconData sIcon; List<Color> btnGrad; String btnLabel; VoidCallback? btnAction;
                      switch (status) {
                        case 'เรียกคิว':
                          statusColor = Colors.blue.shade600; sIcon = Icons.campaign_rounded;
                          btnGrad = [Colors.blue.shade400, Colors.blue.shade700]; btnLabel = 'เริ่มรักษา';
                          btnAction = () => _update(doc.id, 'กำลังรักษา');
                          break;
                        case 'กำลังรักษา':
                          statusColor = Colors.orange.shade700; sIcon = Icons.medical_services_rounded;
                          btnGrad = [Colors.green.shade400, const Color(0xff186B44)]; btnLabel = 'เสร็จสิ้น';
                          btnAction = () => _completeDialog(context, doc.id);
                          break;
                        default:
                          statusColor = primaryGreen; sIcon = Icons.access_time_rounded;
                          btnGrad = [Colors.blue.shade300, Colors.blue.shade700]; btnLabel = 'เรียกคิว';
                          btnAction = () => _update(doc.id, 'เรียกคิว');
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(color: statusColor.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 5)),
                            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              // Accent bar
                              Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [statusColor.withValues(alpha: 0.6), statusColor], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                                ),
                              ),
                              // Card body
                              Expanded(child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  // Top row: queue no + status + time
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(
                                      padding: const EdgeInsets.all(9),
                                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
                                      child: Icon(sIcon, color: statusColor, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('คิว ${data['queueNo'] ?? '-'}', style: GoogleFonts.prompt(fontSize: 24, fontWeight: FontWeight.bold, color: textDark, height: 1.1)),
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                                        child: Text(status, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                    ])),
                                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: [statusColor.withValues(alpha: 0.7), statusColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(data['time'] ?? '-', style: GoogleFonts.prompt(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(data['date'] ?? '', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 11)),
                                    ]),
                                  ]),
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, thickness: 0.5),
                                  const SizedBox(height: 10),
                                  // Patient info
                                  Row(children: [
                                    CircleAvatar(radius: 16, backgroundColor: lightGreen, child: Text((data['patientName'] ?? '?').toString().characters.first, style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 13))),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(data['patientName'] ?? '-', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w700, color: textDark)),
                                      Text(data['doctor'] ?? '-', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)),
                                    ])),
                                  ]),
                                  const SizedBox(height: 12),
                                  // Action button full-width
                                  GestureDetector(
                                    onTap: btnAction,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: btnGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [BoxShadow(color: btnGrad.last.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                                      ),
                                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Icon(sIcon, color: Colors.white, size: 17),
                                        const SizedBox(width: 8),
                                        Text(btnLabel, style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              )),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ]);
        },
      ),
      ),
    );
  }

  Widget _qStatBlock(String label, int count, Color color, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count', style: GoogleFonts.prompt(color: color, fontWeight: FontWeight.bold, fontSize: 18, height: 1.1)),
          Text(label, style: GoogleFonts.notoSansThai(color: color.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
      ]),
    ),
  );
}

// Staff: SOS Screen
class StaffSOSScreen extends StatefulWidget {
  const StaffSOSScreen({super.key});
  @override
  State<StaffSOSScreen> createState() => _StaffSOSScreenState();
}

class _StaffSOSScreenState extends State<StaffSOSScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> resolve(String docId) async => FirebaseFirestore.instance.collection('sos_alerts').doc(docId).update({'status': 'รับเรื่องแล้ว', 'resolvedAt': Timestamp.now()});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xff7F0000), Color(0xffC62828), Color(0xffEF5350)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('แจ้งเหตุฉุกเฉิน SOS', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('ระบบติดตามเหตุฉุกเฉินแบบเรียลไทม์', style: GoogleFonts.notoSansThai(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.4))),
                  child: Row(children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('LIVE', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            TabBar(
              controller: _tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.notoSansThai(fontSize: 13),
              tabs: const [Tab(text: 'รอรับเรื่อง'), Tab(text: 'ประวัติ SOS')],
            ),
          ])),
        ),
        Expanded(child: TabBarView(controller: _tab, children: [_pending(), _history()])),
      ]),
    );
  }

  Widget _pending() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('sos_alerts').where('status', isEqualTo: 'รอรับเรื่อง').snapshots(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.red));
      if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Image.asset('assets/hart.png', width: 120),
        const SizedBox(height: 18),
        Text('ไม่มีเหตุฉุกเฉินในขณะนี้', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('สถานการณ์ปลอดภัย', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 13)),
      ]));
      var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
      return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), itemCount: docs.length, itemBuilder: (_, i) {
        var doc = docs[i]; var data = doc.data() as Map<String, dynamic>;
        DateTime dt = (data['createdAt'] as Timestamp).toDate();
        String timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.red.shade100, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.red.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 6)),
              BoxShadow(color: Colors.red.withValues(alpha: 0.07), blurRadius: 40, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.red.shade700, Colors.red.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('มีผู้ขอความช่วยเหลือ!', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  Text('เวลา $timeStr น.', style: GoogleFonts.notoSansThai(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.5))),
                  child: Text('⚠ ด่วน!', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ]),
            ),
            Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.medical_information_outlined, size: 16, color: Colors.red.shade600), const SizedBox(width: 8), Expanded(child: Text('อาการ: ${data['issue'] ?? '-'}', style: GoogleFonts.notoSansThai(fontSize: 14, fontWeight: FontWeight.w700, color: textDark)))]),
              const SizedBox(height: 6),
              Row(children: [Icon(Icons.person_outline, size: 16, color: Colors.grey.shade400), const SizedBox(width: 8), Text(data['patientName'] ?? 'ไม่ระบุ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 13))]),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => resolve(doc.id),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.red.shade700, Colors.red.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.directions_run_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('รับเรื่อง / เข้าช่วยเหลือทันที', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ]),
                ),
              ),
            ])),
          ]),
        );
      });
    },
  );

  Widget _history() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('sos_alerts').where('status', isEqualTo: 'รับเรื่องแล้ว').snapshots(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
      if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_toggle_off_rounded, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Text('ยังไม่มีประวัติ SOS', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 16)),
      ]));
      var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
      return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), itemCount: docs.length, itemBuilder: (_, i) {
        var data = docs[i].data() as Map<String, dynamic>;
        DateTime dt = (data['createdAt'] as Timestamp).toDate();
        String dateStr = '${dt.day}/${dt.month}/${dt.year + 543}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.';
        return Container(margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 3))]),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.check_circle_rounded, color: primaryGreen, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['issue'] ?? '-', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
              const SizedBox(height: 3),
              Text(data['patientName'] ?? '-', style: GoogleFonts.notoSansThai(color: Colors.grey.shade600, fontSize: 12)),
              Text(dateStr, style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 11)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(10)),
              child: Text('รับเรื่องแล้ว', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 11))),
          ])),
        );
      });
    },
  );
}

// Staff: Treatment History — เลือกวันได้
class StaffTreatmentHistoryScreen extends StatefulWidget {
  const StaffTreatmentHistoryScreen({super.key});
  @override
  State<StaffTreatmentHistoryScreen> createState() => _StaffTreatmentHistoryScreenState();
}

class _StaffTreatmentHistoryScreenState extends State<StaffTreatmentHistoryScreen> {
  DateTime? selectedDate;

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    String? filterDate = selectedDate != null ? _fmtDate(selectedDate!) : null;
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(bottom: false, child: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.history_rounded, color: primaryGreen, size: 22)),
              const SizedBox(width: 12),
              Text('ประวัติการรักษา', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: selectedDate != null ? primaryGreen.withValues(alpha: 0.4) : Colors.transparent)),
                    child: Row(children: [
                      const Icon(Icons.calendar_month_rounded, color: primaryGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(selectedDate != null ? 'วันที่: $filterDate' : 'เลือกวันที่เพื่อกรอง', style: GoogleFonts.notoSansThai(color: selectedDate != null ? primaryGreen : Colors.grey.shade600, fontWeight: FontWeight.w500, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              if (selectedDate != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => selectedDate = null),
                  child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.close_rounded, color: Colors.red, size: 18)),
                ),
              ],
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('appointments').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xff00897b)));
              if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.history_rounded, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('ยังไม่มีประวัติ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 16)),
              ]));
              var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
              if (filterDate != null) docs = docs.where((d) => (d.data() as Map)['date'] == filterDate).toList();
              if (docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.search_off_rounded, size: 72, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('ไม่พบประวัติวันที่ $filterDate', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 15)),
              ]));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  var data = docs[i].data() as Map<String, dynamic>;
                  String status = data['status'] ?? 'กำลังรอ';
                  Color sc; IconData sIcon;
                  switch (status) {
                    case 'เสร็จสิ้น': sc = const Color(0xff2e7d32); sIcon = Icons.check_circle_rounded; break;
                    case 'กำลังรักษา': sc = const Color(0xffe65100); sIcon = Icons.medical_services_rounded; break;
                    case 'เรียกคิว': sc = const Color(0xff1565c0); sIcon = Icons.campaign_rounded; break;
                    case 'ยกเลิก': sc = Colors.red.shade700; sIcon = Icons.cancel_rounded; break;
                    default: sc = const Color(0xff2d6a4f); sIcon = Icons.access_time_rounded;
                  }
                  String notes = (data['notes'] ?? '').toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: sc.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)), BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 5)],
                    ),
                    child: Padding(padding: const EdgeInsets.all(15), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [sc.withValues(alpha: 0.7), sc], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: sc.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                      ), child: Icon(sIcon, color: Colors.white, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('คิว ${data['queueNo'] ?? '-'}', style: GoogleFonts.prompt(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                          const Spacer(),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: Text(status, style: GoogleFonts.notoSansThai(color: sc, fontWeight: FontWeight.bold, fontSize: 11))),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade400), const SizedBox(width: 5), Text(data['patientName'] ?? '-', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, fontSize: 13, color: textDark))]),
                        const SizedBox(height: 3),
                        Row(children: [Icon(Icons.local_hospital_outlined, size: 14, color: Colors.grey.shade400), const SizedBox(width: 5), Expanded(child: Text(data['doctor'] ?? '-', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)))]),
                        const SizedBox(height: 3),
                        Row(children: [Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade400), const SizedBox(width: 5), Text('${data['date'] ?? ''}  ${data['time'] ?? ''}', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 12))]),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(10)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.note_alt_outlined, size: 14, color: primaryGreen), const SizedBox(width: 6), Expanded(child: Text(notes, style: GoogleFonts.notoSansThai(fontSize: 12, color: primaryGreen)))])),
                        ],
                      ])),
                    ])),
                  );
                },
              );
            },
          ),
        ),
      ])),
    );
  }
}

// Staff: Availability Screen
class StaffAvailabilityScreen extends StatefulWidget {
  const StaffAvailabilityScreen({super.key});
  @override
  State<StaffAvailabilityScreen> createState() => _StaffAvailabilityScreenState();
}

class _StaffAvailabilityScreenState extends State<StaffAvailabilityScreen> {
  int selectedDateIndex = 0;
  Set<String> selectedTimes = {};
  bool isSaving = false;
  bool isLoading = false;
  bool isLocked = false;
  late List<DateTime> upcomingDays;
  final List<String> thaiDayNames = ['', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

  @override
  void initState() {
    super.initState();
    upcomingDays = List.generate(14, (i) => DateTime.now().add(Duration(days: i)));
    for (int i = 0; i < upcomingDays.length; i++) {
      if (upcomingDays[i].weekday != DateTime.saturday && upcomingDays[i].weekday != DateTime.sunday) {
        selectedDateIndex = i; break;
      }
    }
    _load();
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';
  String _docId() => '${FirebaseAuth.instance.currentUser?.uid ?? 'staff'}_${_fmt(upcomingDays[selectedDateIndex])}';

  Future<void> _load() async {
    setState(() { isLoading = true; selectedTimes = {}; isLocked = false; });
    try {
      var docSnap = await FirebaseFirestore.instance.collection('staff_availability').doc(_docId()).get();
      if (docSnap.exists && mounted) {
        final raw = docSnap.data()?['times'];
        if (raw is List) setState(() { selectedTimes = Set<String>.from(raw.map((e) => e.toString())); isLocked = true; });
      }
    } catch (_) {}
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _save() async {
    setState(() => isSaving = true);
    try {
      String dateStr = _fmt(upcomingDays[selectedDateIndex]);
      List<String> sorted = selectedTimes.toList()..sort((a, b) {
        final aP = a.split(':'); final bP = b.split(':');
        int aMin = int.parse(aP[0]) * 60 + int.parse(aP[1]);
        int bMin = int.parse(bP[0]) * 60 + int.parse(bP[1]);
        return aMin.compareTo(bMin);
      });
      await FirebaseFirestore.instance.collection('staff_availability').doc(_docId()).set({'staffUid': FirebaseAuth.instance.currentUser?.uid ?? '', 'date': dateStr, 'times': sorted, 'updatedAt': Timestamp.now()});
      if (mounted) { setState(() => isLocked = true); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกเวลาว่างสำหรับ $dateStr แล้ว'), backgroundColor: Colors.green)); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now(), builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (picked != null && mounted) {
      String t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() => selectedTimes.add(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    List<String> sortedSelected = selectedTimes.toList()..sort((a, b) {
      final aP = a.split(':'); final bP = b.split(':');
      return (int.parse(aP[0]) * 60 + int.parse(aP[1])).compareTo(int.parse(bP[0]) * 60 + int.parse(bP[1]));
    });
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(bottom: false, child: Column(children: [
        // White header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.schedule_rounded, color: primaryGreen, size: 22)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ตั้งเวลาว่าง', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                Text('เลือกวันและช่วงเวลาที่พร้อมให้บริการ', style: GoogleFonts.notoSansThai(color: Colors.grey.shade500, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 14),
            SizedBox(height: 72, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: upcomingDays.length, itemBuilder: (_, i) {
              DateTime date = upcomingDays[i];
              bool isWe = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
              bool isSel = i == selectedDateIndex;
              return GestureDetector(
                onTap: isWe ? null : () { setState(() => selectedDateIndex = i); _load(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56, margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isSel ? primaryGreen : (isWe ? Colors.grey.shade100 : lightGreen),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(thaiDayNames[date.weekday], style: TextStyle(color: isSel ? Colors.white70 : (isWe ? Colors.grey : primaryGreen), fontWeight: FontWeight.bold, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(date.day.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isSel ? Colors.white : (isWe ? Colors.grey : primaryGreen))),
                    if (isWe) Text('หยุด', style: TextStyle(fontSize: 9, color: isSel ? Colors.white60 : Colors.grey.shade400)),
                  ]),
                ),
              );
            })),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('ช่วงเวลาที่เปิด', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 16, color: textDark)),
                const Spacer(),
                if (isLocked) GestureDetector(
                  onTap: () => setState(() => isLocked = false),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: lightGreen, border: Border.all(color: primaryGreen.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit_rounded, color: primaryGreen, size: 15),
                      const SizedBox(width: 5),
                      Text('แก้ไข', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    ])),
                ),
              ]),
              const SizedBox(height: 14),
              if (isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: primaryGreen)))
              else if (isLocked) ...[
                sortedSelected.isEmpty
                  ? Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.orange.shade200)),
                      child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange), const SizedBox(width: 10), Expanded(child: Text('ยังไม่มีเวลาว่างที่บันทึกไว้', style: GoogleFonts.notoSansThai(color: Colors.orange.shade800, fontWeight: FontWeight.w500)))]))
                  : Wrap(spacing: 10, runSpacing: 10, children: sortedSelected.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryGreen.withValues(alpha: 0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.access_time_rounded, color: primaryGreen, size: 15),
                        const SizedBox(width: 6),
                        Text(t, style: GoogleFonts.prompt(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                      ]),
                    )).toList()),
              ] else ...[
                if (sortedSelected.isNotEmpty) ...[
                  Wrap(spacing: 10, runSpacing: 10, children: sortedSelected.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: lightGreen, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryGreen.withValues(alpha: 0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.access_time_rounded, color: primaryGreen, size: 15),
                      const SizedBox(width: 6),
                      Text(t, style: GoogleFonts.prompt(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      GestureDetector(onTap: () => setState(() => selectedTimes.remove(t)), child: const Icon(Icons.close_rounded, size: 15, color: Colors.red)),
                    ]),
                  )).toList()),
                  const SizedBox(height: 14),
                ],
                GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: primaryGreen.withValues(alpha: 0.3), width: 1.5)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_alarm_rounded, color: primaryGreen),
                      const SizedBox(width: 8),
                      Text('+ เพิ่มช่วงเวลา', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
                  color: selectedTimes.isEmpty ? Colors.orange.shade50 : lightGreen,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selectedTimes.isEmpty ? Colors.orange.shade200 : primaryGreen.withValues(alpha: 0.2)),
                ), child: Row(children: [
                  Icon(selectedTimes.isEmpty ? Icons.warning_amber_rounded : Icons.check_circle_rounded, color: selectedTimes.isEmpty ? Colors.orange : primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(child: Text(selectedTimes.isEmpty ? 'ยังไม่ได้เลือกช่วงเวลา' : 'เลือกแล้ว ${selectedTimes.length} ช่วงเวลา', style: GoogleFonts.notoSansThai(color: selectedTimes.isEmpty ? Colors.orange.shade800 : primaryGreen, fontWeight: FontWeight.w500))),
                ])),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: isSaving ? null : _save,
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: isSaving ? Colors.grey.shade200 : primaryGreen,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSaving ? [] : [BoxShadow(color: primaryGreen.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Center(child: isSaving
                      ? const CircularProgressIndicator(color: primaryGreen)
                      : Text('บันทึกเวลาว่าง', style: GoogleFonts.notoSansThai(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ])),
    );
  }
}

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
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(FirebaseFirestore.instance.collection('users').doc(uid));
      final appts = await FirebaseFirestore.instance.collection('appointments').where('patientUid', isEqualTo: uid).get();
      for (var d in appts.docs) { batch.delete(d.reference); }
      final apptsSt = await FirebaseFirestore.instance.collection('appointments').where('staffUid', isEqualTo: uid).get();
      for (var d in apptsSt.docs) { batch.delete(d.reference); }
      final avail = await FirebaseFirestore.instance.collection('staff_availability').where('staffUid', isEqualTo: uid).get();
      for (var d in avail.docs) { batch.delete(d.reference); }
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ลบบัญชี "$name" เรียบร้อยแล้ว'), backgroundColor: primaryGreen));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
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
                  onTap: () => FirebaseAuth.instance.signOut(),
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
    stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: role).snapshots(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: primaryGreen));
      final docs = (snap.data?.docs ?? []).where((d) {
        final name = ((d.data() as Map)['fullname'] ?? '').toString().toLowerCase();
        final email = ((d.data() as Map)['email'] ?? '').toString().toLowerCase();
        return _search.isEmpty || name.contains(_search) || email.contains(_search);
      }).toList();
      if (docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.person_off_rounded, color: Colors.grey.shade300, size: 56),
        const SizedBox(height: 12),
        Text('ไม่พบผู้ใช้', style: GoogleFonts.notoSansThai(color: Colors.grey.shade400, fontSize: 15)),
      ]));
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final data = docs[i].data() as Map<String, dynamic>;
          final uid = docs[i].id;
          final name = data['fullname'] ?? 'ไม่ระบุชื่อ';
          final email = data['email'] ?? '';
          final photo = data['photoBase64'] ?? '';
          ImageProvider? photoImg;
          if (photo.isNotEmpty) { try { photoImg = MemoryImage(base64Decode(photo)); } catch (_) {} }
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


//test
//git add .
//git commit -m "junjj" ตั้งชื่อ
//git push -u origin main