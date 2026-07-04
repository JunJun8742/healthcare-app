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
            String role = 'patient';
            if (userSnap.hasData && userSnap.data!.exists) {
              role = (userSnap.data!.data() as Map<String, dynamic>)['role'] ?? 'patient';
            }
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
