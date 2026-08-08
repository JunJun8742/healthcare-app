import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/fcm_service.dart';
import 'package:healthcare_app/features/auth/login_screen.dart';
import 'package:healthcare_app/features/patient/main_navigation.dart';
import 'package:healthcare_app/features/staff/staff_navigation.dart';
import 'package:healthcare_app/features/admin/admin_navigation.dart';

// ===== Navigator key เดียวของแอป — ใช้โดย MaterialApp และการนำทางจากแจ้งเตือน =====
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class HealthcareStation extends StatelessWidget {
  const HealthcareStation({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Healthcare Station',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th'), Locale('en')],
      locale: const Locale('th'),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4);
        return MediaQuery(data: mq.copyWith(textScaler: clamped), child: child!);
      },
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bgWhite,
        colorSchemeSeed: primaryGreen,
        materialTapTargetSize: MaterialTapTargetSize.padded,
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
// Push notifications: tap routing (ฝั่ง widget)
// ==========================================
// แปลงปลายทางจากตารางตัดสินใจใน fcm_service เป็นหน้าจอจริง แล้วนำทางผ่าน appNavigatorKey
void routeFromNotification(String? type) {
  final dest = notificationDestination(role: currentUserRole, type: type);
  if (dest == null) return;
  final Widget root = switch (dest) {
    NotifDestination.patientQueue => const MainNavigation(initialIndex: 1),
    NotifDestination.staffSos => const StaffNavigation(initialIndex: 1),
    NotifDestination.staffQueue => const StaffNavigation(initialIndex: 0),
  };
  appNavigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => root), (r) => false);
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
        if (!authSnap.hasData) {
          resetFcmRegistration();
          currentUserRole = null;
          return const LoginScreen();
        }

        // อ่าน role จาก Firestore
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(authSnap.data!.uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final docExists = userSnap.hasData && userSnap.data!.exists;

            // No users/{uid} doc at all == a patient signup still pending
            // email verification (register_screen.dart deliberately skips
            // this write until verified, so an abandoned signup leaves no
            // Firestore data behind). Staff/admin docs always exist from the
            // moment the account is created, so this path is patient-only.
            if (!docExists) {
              return const _EmailVerificationGate();
            }

            String role = (userSnap.data!.data() as Map<String, dynamic>)['role'] ?? 'patient';
            currentUserRole = role;
            final uid = authSnap.data!.uid;

            if (!fcmRegistered) {
              WidgetsBinding.instance.addPostFrameCallback((_) => registerFcm(uid, onNotificationTap: routeFromNotification));
            }

            // ปลายทางค้างจากการแตะแจ้งเตือนตอนแอปปิดอยู่ (getInitialMessage) — ใช้ครั้งเดียวแล้วเคลียร์ทิ้ง
            if (pendingNotifType != null) {
              final type = pendingNotifType;
              pendingNotifType = null;
              final dest = notificationDestination(role: role, type: type);
              if (dest != null) {
                return switch (dest) {
                  NotifDestination.patientQueue => const MainNavigation(initialIndex: 1),
                  NotifDestination.staffSos => const StaffNavigation(initialIndex: 1),
                  NotifDestination.staffQueue => const StaffNavigation(initialIndex: 0),
                };
              }
            }

            if (role == 'staff') return const StaffNavigation();
            if (role == 'admin') return const AdminNavigation();
            return const MainNavigation();
          },
        );
      },
    );
  }
}

// ==========================================
// Blocking screen for accounts that must verify email before entering the
// app (see requiresEmailVerification on users/{uid}). Not a StreamBuilder —
// FirebaseAuth's User.emailVerified is a point-in-time snapshot, so the
// patient must explicitly ask us to re-check after clicking the email link.
// ==========================================
class _EmailVerificationGate extends StatefulWidget {
  const _EmailVerificationGate();

  @override
  State<_EmailVerificationGate> createState() => _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<_EmailVerificationGate> {
  bool _checking = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Silent auto-check on mount — covers returning to the app after
    // verifying via the email link elsewhere, without making the user find
    // and tap the button themselves.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVerified(silent: true));
  }

  // Writes users/{uid} (role: patient) the FIRST time we can prove the
  // address is verified — this is the only place that Firestore doc gets
  // created for a patient signup (see register_screen.dart, which
  // deliberately skips it). fullname comes from the Auth displayName set at
  // signup since no Firestore data exists yet to read it from.
  Future<void> _finalizePatientDoc(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      'uid': user.uid,
      'fullname': user.displayName ?? 'ผู้ใช้งาน',
      'email': user.email ?? '',
      'role': 'patient',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _checkVerified({bool silent = false}) async {
    setState(() => _checking = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      final freshUser = FirebaseAuth.instance.currentUser;
      final verified = freshUser?.emailVerified ?? false;
      if (!mounted || freshUser == null) return;
      if (verified) {
        await _finalizePatientDoc(freshUser);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainNavigation()), (r) => false);
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยังไม่ได้ยืนยันอีเมล กรุณากดลิงก์ในอีเมลก่อน')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await user.sendEmailVerification();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งอีเมลยืนยันแล้ว กรุณาตรวจสอบกล่องจดหมาย (รวมถึงโฟลเดอร์สแปม)')));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'too-many-requests'
          ? 'ส่งไปแล้วเมื่อครู่นี้ — Firebase จำกัดไม่ให้ส่งถี่เกินไป กรุณารออีกสักครู่แล้วเช็คอีเมล/สแปมก่อนกดส่งซ้ำ'
          : 'ส่งไม่สำเร็จ (${e.code}) กรุณาลองใหม่ภายหลัง';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งไม่สำเร็จ กรุณาลองใหม่ภายหลัง')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _logout() async {
    await removeFcmTokenBeforeLogout();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.mark_email_unread_rounded, size: 72, color: primaryGreen),
              const SizedBox(height: 20),
              Text('กรุณายืนยันอีเมลของคุณ', style: GoogleFonts.notoSansThai(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
              const SizedBox(height: 10),
              Text(
                'เราได้ส่งลิงก์ยืนยันไปที่\n$email\nกรุณากดลิงก์ในอีเมล แล้วกลับมากด "ตรวจสอบอีกครั้ง"',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansThai(color: textSecondary, height: 1.5),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Flexible(child: Text('ไม่เจออีเมล? ลองเช็คโฟลเดอร์สแปม/จดหมายขยะด้วย', style: GoogleFonts.notoSansThai(fontSize: 12.5, color: Colors.amber.shade900))),
                ]),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 240, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: _checking ? null : _checkVerified,
                  child: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('ตรวจสอบอีกครั้ง', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _sending ? null : _resend,
                child: Text(_sending ? 'กำลังส่ง...' : 'ส่งอีเมลยืนยันอีกครั้ง', style: GoogleFonts.notoSansThai(color: primaryGreen, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _logout,
                child: Text('ออกจากระบบ', style: GoogleFonts.notoSansThai(color: Colors.grey)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
