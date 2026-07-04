import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/core/status.dart';
import 'package:healthcare_app/core/widgets.dart';
import 'package:healthcare_app/services/fcm_service.dart';
import 'package:healthcare_app/services/appointment_service.dart';
import 'package:healthcare_app/services/queue_slot_service.dart';
import 'package:healthcare_app/services/availability_service.dart';
import 'package:healthcare_app/services/user_service.dart';
import 'package:healthcare_app/services/notification_service.dart';
import 'package:healthcare_app/features/auth/login_screen.dart';
import 'package:healthcare_app/features/patient/notification_screen.dart';
import 'package:healthcare_app/features/patient/sos_screen.dart';
import 'package:healthcare_app/features/patient/history_screen.dart';
import 'package:healthcare_app/features/patient/active_queue_screen.dart';
import 'package:healthcare_app/features/staff/staff_queue_screen.dart';
import 'package:healthcare_app/features/staff/staff_sos_screen.dart';
import 'package:healthcare_app/features/staff/staff_history_screen.dart';
import 'package:healthcare_app/features/staff/staff_availability_screen.dart';
import 'package:healthcare_app/features/admin/admin_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initFcmBootstrap(onNotificationTap: routeFromNotification);
  runApp(const HealthcareStation());
}

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

// ==========================================
// 4. Main Navigation (Patient)
// ==========================================
class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({super.key, this.initialIndex = 0});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int index;
  final pages = [const HomeScreen(), const ActiveQueueScreen(), const HistoryScreen(), const ProfileScreen()];

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
  }

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
        future: users.getUser(user?.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
          }
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
                        Text('จองคิวกายภาพบำบัด', style: tCaption()),
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
                      stream: appointments.patientAppointments(user?.uid),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return const StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง');
                        }
                        String qNo = ''; String status = ''; String? activeDocId;
                        String time = ''; String activeStaffUid = ''; String activeDate = '';
                        if (snap.hasData && snap.data!.docs.isNotEmpty) {
                          var docs = snap.data!.docs.toList()..sort((a, b) { final ta = a['createdAt'] as Timestamp?; final tb = b['createdAt'] as Timestamp?; if (tb == null) return -1; if (ta == null) return 1; return tb.compareTo(ta); });
                          var latest = docs.first;
                          if (!['เสร็จสิ้น', 'ยกเลิก'].contains(latest['status'])) {
                            qNo = latest['queueNo'] ?? '';
                            status = latest['status'] ?? '';
                            activeDocId = latest.id;
                            time = latest['time'] ?? '';
                            activeStaffUid = latest['staffUid'] ?? '';
                            activeDate = latest['date'] ?? '';
                          }
                        }
                        final bool hasQueue = qNo.isNotEmpty;
                        final s = statusInfo(status);
                        Color statusColor = s.color;

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
                                    Text('คิวของคุณวันนี้', style: GoogleFonts.notoSansThai(fontSize: 14, color: textSecondary, fontWeight: FontWeight.w500)),
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
                                        Icon(s.icon, size: 14, color: statusColor),
                                        const SizedBox(width: 6),
                                        Text(s.label, style: GoogleFonts.notoSansThai(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ]),
                                    ),
                                    const SizedBox(height: 12),
                                    if (time.isNotEmpty)
                                      Row(children: [
                                        Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                                        const SizedBox(width: 6),
                                        Text('นัดเวลา $time', style: GoogleFonts.notoSansThai(color: textSecondary, fontSize: 14)),
                                      ]),
                                    if (activeDocId != null && status == 'กำลังรอ') ...[
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: () => _confirmCancel(context, activeDocId!, staffUid: activeStaffUid, date: activeDate, time: time),
                                        child: Text('ยกเลิกคิว', style: GoogleFonts.notoSansThai(color: Colors.red.shade400, fontSize: 14, decoration: TextDecoration.underline)),
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
                                    Text('ยังไม่มีคิว — กดปุ่มด้านล่างเพื่อจองคิวแรกของคุณ', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 15, color: textDark)),
                                  ])),
                                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textSecondary),
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
                      Expanded(child: Stack(clipBehavior: Clip.none, children: [
                        _serviceCard(context, 'แจ้งเตือน', Icons.notifications_rounded, false, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen()))),
                        Positioned(
                          top: 8, right: 8,
                          child: StreamBuilder<QuerySnapshot>(
                            stream: notifications.unreadProbe(user?.uid),
                            builder: (context, unreadSnap) {
                              final hasUnread = unreadSnap.data?.docs.isNotEmpty ?? false;
                              if (!hasUnread) return const SizedBox.shrink();
                              return Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                              );
                            },
                          ),
                        ),
                      ])),
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

  void _confirmCancel(BuildContext context, String docId, {String staffUid = '', String date = '', String time = ''}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 10), Text('ยืนยันการยกเลิกคิว', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        content: Text('คุณต้องการยกเลิกคิวนี้ใช่หรือไม่?\nไม่สามารถนำคิวกลับคืนได้', style: TextStyle(color: textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('ไม่ยกเลิก', style: TextStyle(color: textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await appointments.cancelByPatient(docId);
                if (staffUid.isNotEmpty && date.isNotEmpty && time.isNotEmpty) {
                  queueSlots.release(staffUid: staffUid, date: date, time: time);
                }
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคิวเรียบร้อยแล้ว'), backgroundColor: Colors.red));
              } catch (e) {
                // กติกาความปลอดภัยยอมให้ยกเลิกเฉพาะคิวที่ยัง 'กำลังรอ' — ถ้าเจ้าหน้าที่เรียกคิวตัดหน้าไปแล้ว การยกเลิกจะถูกปฏิเสธ
                debugPrint('cancel appointment failed: $e');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคิวไม่สำเร็จ คิวอาจถูกเรียกไปแล้ว กรุณาลองใหม่'), backgroundColor: Colors.orange));
              }
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
          icon3D(icon, [const Color(0xff1b4332), const Color(0xff52b788)], 60),
          const SizedBox(height: 14),
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, color: textDark, fontSize: 14), textAlign: TextAlign.center),
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
          icon3D(icon, iconColors, 58),
          const SizedBox(height: 10),
          // 13px is the single allowed exception to the 14px minimum: 3-column layout, label duplicated by icon above.
          Text(title, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600, fontSize: 13, color: textDark), textAlign: TextAlign.center),
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

  bool get _canSubmit => staffList.isNotEmpty && availableTimes.isNotEmpty && selectedMachineId != null && !loadingTimes && !loadingStaff;

  String get _missingHint {
    if (loadingStaff || loadingTimes) return 'กำลังโหลดข้อมูล...';
    if (staffList.isEmpty) return 'ยังไม่มีเจ้าหน้าที่ให้เลือก';
    if (availableTimes.isEmpty) return 'ไม่มีเวลาว่างในวันนี้ กรุณาเลือกวันอื่น';
    if (selectedMachineId == null) return 'กรุณาเลือกเครื่องที่ใช้';
    return '';
  }

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
      var staffData = await users.staffUsers();
      if (mounted) setState(() { staffList = staffData; loadingStaff = false; });
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
      List<String> times = await availability.openTimes(staffUid: staffUid, date: dateStr);
      Map<String, dynamic> bookedTimesMap = await availability.bookedTimes(staffUid: staffUid, date: dateStr);
      List<String> freeTimes = times.where((t) => bookedTimesMap[t] == null || bookedTimesMap[t] == false).toList();
      if (mounted) setState(() { availableTimes = freeTimes; selectedTimeIndex = 0; loadingTimes = false; });
    } catch (_) {
      if (mounted) setState(() { availableTimes = []; loadingTimes = false; });
    }
  }

  Future<BookingOutcome> submitBooking() async {
    try {
      setState(() => isSubmitting = true);
      User? user = FirebaseAuth.instance.currentUser;
      final outcome = await appointments.createBooking(
        patientUid: user!.uid,
        doctor: staffList.isNotEmpty ? (staffList[selectedStaffIndex]['fullname'] ?? 'นักกายภาพ') : 'นักกายภาพ',
        staffUid: staffList.isNotEmpty ? (staffList[selectedStaffIndex]['uid'] ?? '') : '',
        date: _fmt(upcomingDays[selectedDateIndex]),
        time: availableTimes[selectedTimeIndex],
        machineId: selectedMachineId ?? '',
        machineName: selectedMachineName,
      );
      // Snackbar อธิบายเหตุจองไม่ได้เพราะมีคิวค้าง — sheet จะปิดตัวเฉย ๆ ไม่ซ้อน error
      if (outcome is BookingBlockedByActiveQueue && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณมีคิวที่ยังไม่เสร็จสิ้นอยู่แล้ว'), backgroundColor: Colors.orange));
      }
      return outcome;
    } catch (e) {
      return const BookingFailed();
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _showConfirmSheet() {
    final staff = staffList[selectedStaffIndex];
    final dateStr = _fmt(upcomingDays[selectedDateIndex]);
    final time = availableTimes[selectedTimeIndex];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        bool submitting = false;
        String? error;
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          Widget row(IconData ic, String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(ic, color: primaryGreen, size: 22),
              const SizedBox(width: kGapM),
              Text(label, style: tCaption()),
              const Spacer(),
              Flexible(child: Text(value, style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.end)),
            ]),
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('ยืนยันการจองคิว', style: tTitle(), textAlign: TextAlign.center),
              const SizedBox(height: kGapL),
              row(Icons.person_rounded, 'เจ้าหน้าที่', staff['fullname'] ?? 'นักกายภาพ'),
              row(Icons.calendar_month_rounded, 'วันที่', dateStr),
              row(Icons.access_time_rounded, 'เวลา', time),
              if (error != null) ...[
                const SizedBox(height: kGapM),
                Text(error!, style: tCaption(const Color(0xffB91C1C)), textAlign: TextAlign.center),
              ],
              const SizedBox(height: kGapXL),
              SizedBox(height: 56, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
                onPressed: submitting ? null : () async {
                  setSheet(() { submitting = true; error = null; });
                  final outcome = await submitBooking();
                  if (!sheetCtx.mounted) return;
                  if (outcome is BookingBlockedByActiveQueue) {
                    // Orange snackbar (shown by submitBooking) already explains
                    // this outcome — just close the sheet, no in-sheet error.
                    Navigator.pop(sheetCtx);
                  } else if (outcome is BookingSuccess) {
                    Navigator.pop(sheetCtx);
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => BookingSuccessScreen(
                        queueNo: outcome.queueNo,
                        doctor: staffList[selectedStaffIndex]['fullname'] ?? 'นักกายภาพ',
                        date: _fmt(upcomingDays[selectedDateIndex]),
                        time: availableTimes[selectedTimeIndex],
                        machineName: selectedMachineName,
                      )), (r) => false);
                    }
                  } else {
                    setSheet(() { submitting = false; error = 'จองไม่สำเร็จ ช่วงเวลานี้อาจถูกจองแล้ว กรุณาเลือกเวลาใหม่'; });
                    _loadAvailability();
                  }
                },
                child: submitting
                    ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Text('ยืนยันการจอง', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
              )),
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(sheetCtx),
                child: Text('ยกเลิก', style: tBody(textSecondary)),
              ),
            ]),
          );
        });
      },
    );
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
              step: 1, icon: Icons.calendar_month_rounded, title: '1. เลือกวันที่นัดหมาย',
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
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: isWeekend ? Colors.grey.shade100 : (isSel ? primaryGreen : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: isSel ? null : Border.all(color: isWeekend ? Colors.grey.shade200 : lightGreen),
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
            const SizedBox(height: kGapXL),

            // ── Step 2: นักกายภาพ ──
            _bookingCard(
              step: 2, icon: Icons.person_rounded, title: '2. เลือกนักกายภาพ',
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
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: isSel ? lightGreen : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSel ? primaryGreen : lightGreen, width: isSel ? 1.5 : 1),
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
            const SizedBox(height: kGapXL),

            // ── Step 3: เครื่อง ──
            _bookingCard(
              step: 3, icon: Icons.computer_rounded, title: '3. เลือกเครื่องที่ใช้',
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
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: isSel ? primaryGreen : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSel ? primaryGreen : lightGreen, width: isSel ? 1.5 : 1),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(color: isSel ? Colors.white.withValues(alpha: 0.2) : sColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(sIcon, color: isSel ? Colors.white : sColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: GoogleFonts.notoSansThai(fontWeight: FontWeight.bold, fontSize: 14, color: isSel ? Colors.white : textDark)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: isSel ? Colors.white.withValues(alpha: 0.2) : sColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text(sText, style: GoogleFonts.notoSansThai(fontSize: 11, color: isSel ? Colors.white : sColor, fontWeight: FontWeight.w600)),
                            ),
                          ])),
                          if (isSel) Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, color: primaryGreen, size: 15),
                          ),
                        ]),
                      ),
                    );
                  }).toList());
                },
              ),
            ),
            const SizedBox(height: kGapXL),

            // ── Step 4: เวลา ──
            _bookingCard(
              step: 4, icon: Icons.access_time_rounded, title: '4. เลือกเวลา',
              child: loadingTimes
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: primaryGreen)))
                : availableTimes.isEmpty
                  ? _infoBox('ไม่มีช่วงเวลาที่เปิดในวันนี้', Colors.orange)
                  : GridView.builder(
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.7, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: availableTimes.length,
                      itemBuilder: (_, i) {
                        bool isSel = i == selectedTimeIndex;
                        String time = availableTimes[i];
                        return GestureDetector(
                          onTap: () => setState(() => selectedTimeIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            constraints: const BoxConstraints(minHeight: 48),
                            decoration: BoxDecoration(
                              color: isSel ? primaryGreen : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: isSel ? null : Border.all(color: lightGreen),
                              boxShadow: isSel ? [BoxShadow(color: primaryGreen.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))] : [],
                            ),
                            child: Center(child: Text(time, style: GoogleFonts.prompt(fontWeight: FontWeight.bold, fontSize: 15, color: isSel ? Colors.white : textDark))),
                          ),
                        );
                      },
                    ),
            ),

          ]),
        )),

        // ===== Bottom-pinned submit button =====
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_canSubmit)
              Padding(
                padding: const EdgeInsets.only(bottom: kGapS),
                child: Text(_missingHint, style: tCaption(const Color(0xffB7791F))),
              ),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen, foregroundColor: Colors.white,
                  disabledBackgroundColor: primaryGreen.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                ),
                onPressed: _canSubmit && !isSubmitting ? _showConfirmSheet : null,
                child: isSubmitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('จองคิว', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
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
        Expanded(child: Text(title, style: tTitle())),
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
// 6.5 Booking Success Screen
// ==========================================
class BookingSuccessScreen extends StatelessWidget {
  final String queueNo, doctor, date, time, machineName;
  const BookingSuccessScreen({super.key, required this.queueNo, required this.doctor, required this.date, required this.time, required this.machineName});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData ic, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(ic, color: primaryGreen, size: 22),
        const SizedBox(width: kGapM),
        Text(label, style: tCaption()),
        const Spacer(),
        Flexible(child: Text(value, style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.end)),
      ]),
    );
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: lightGreen, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: primaryGreen, size: 60),
          ),
          const SizedBox(height: kGapL),
          Text('จองคิวสำเร็จ', style: GoogleFonts.notoSansThai(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGreen)),
          const SizedBox(height: kGapM),
          Text('หมายเลขคิวของคุณ', style: tCaption()),
          Text(queueNo, style: GoogleFonts.prompt(fontSize: 72, fontWeight: FontWeight.bold, color: primaryGreen)),
          const SizedBox(height: kGapL),
          Container(
            padding: const EdgeInsets.all(kCardPadding),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(kRadius),
              boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              row(Icons.person_rounded, 'เจ้าหน้าที่', doctor),
              row(Icons.calendar_month_rounded, 'วันที่', date),
              row(Icons.access_time_rounded, 'เวลา', time),
              if (machineName.isNotEmpty) row(Icons.precision_manufacturing_rounded, 'เครื่อง', machineName),
            ]),
          ),
          const Spacer(),
          SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 1)), (r) => false),
            child: Text('ดูคิวของฉัน', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: kGapM),
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const MainNavigation()), (r) => false),
            child: Text('กลับหน้าแรก', style: tBody(textSecondary)),
          ),
        ]),
      )),
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

// =======================================================================================
// STAFF SECTION
// =======================================================================================

class StaffNavigation extends StatefulWidget {
  final int initialIndex;
  const StaffNavigation({super.key, this.initialIndex = 0});
  @override
  State<StaffNavigation> createState() => _StaffNavigationState();
}

class _StaffNavigationState extends State<StaffNavigation> {
  late int index;
  final pages = [const StaffQueueScreen(), const StaffSOSScreen(), const StaffTreatmentHistoryScreen(), const StaffAvailabilityScreen(), const ProfileScreen()];

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
  }

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

//test
//git add .
//git commit -m "junjj" ตั้งชื่อ
//git push -u origin main