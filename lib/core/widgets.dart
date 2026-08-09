import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/noshow_offer_service.dart';

// ===== Empty/Error state ที่ใช้ร่วมกัน =====
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  const StateMessage({super.key, required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kGapXL),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: textSecondary),
          const SizedBox(height: kGapM),
          Text(message, style: tBody(textSecondary), textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: kGapL),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen, foregroundColor: Colors.white,
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
              ),
              onPressed: onRetry,
              child: Text('ลองอีกครั้ง', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
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
      builder: (_, _) => Container(
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
// No-show offer banner — คิวก่อนหน้าไม่มาตามนัดเกิน 10 นาทีแล้วถูกยกเลิกอัตโนมัติ
// เสนอให้คิวถัดไปเลือกเวลาที่สะดวกมาเร็วขึ้น (ไม่มีการสลับคิว/เวลาใดๆ — แค่บันทึก
// เจตนา ให้ staff เห็นว่าคนไข้แจ้งว่าจะมาเวลาไหน)
// ==========================================
class NoShowOfferBanner extends StatefulWidget {
  final String apptId;
  final List<String> options;
  const NoShowOfferBanner({super.key, required this.apptId, required this.options});

  @override
  State<NoShowOfferBanner> createState() => _NoShowOfferBannerState();
}

class _NoShowOfferBannerState extends State<NoShowOfferBanner> {
  bool _loading = false;

  Future<void> _respond(String? chosenTime) async {
    setState(() => _loading = true);
    try {
      await noShowOfferService.respond(apptId: widget.apptId, chosenTime: chosenTime);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(chosenTime != null ? 'แจ้งเจ้าหน้าที่แล้วว่าจะมาเวลา $chosenTime' : 'บันทึกว่าไม่สะดวกแล้ว', style: GoogleFonts.notoSansThai()),
          backgroundColor: chosenTime != null ? primaryGreen : Colors.grey.shade600,
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่', style: GoogleFonts.notoSansThai()),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e', style: GoogleFonts.notoSansThai()), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: kGapL),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xff52b788), Color(0xff186B44)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.directions_walk_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text('สนใจเข้ารับบริการไวขึ้นไหม?', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
        ]),
        const SizedBox(height: 8),
        Text('คิวก่อนหน้าไม่มาตามนัด สะดวกมาเวลาไหนแจ้งเจ้าหน้าที่ได้เลย', style: GoogleFonts.notoSansThai(color: Colors.white.withValues(alpha: 0.95), fontSize: 13)),
        const SizedBox(height: 14),
        Row(children: [
          for (final t in widget.options) ...[
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primaryGreen, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
              onPressed: _loading ? null : () => _respond(t),
              child: Text(t, style: GoogleFonts.prompt(fontWeight: FontWeight.bold)),
            )),
            const SizedBox(width: 8),
          ],
          Expanded(child: OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
            onPressed: _loading ? null : () => _respond(null),
            child: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('ไม่สนใจ', style: GoogleFonts.notoSansThai(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          )),
        ]),
      ]),
    );
  }
}

// ===== แถบเตือนยืนยันอีเมล =====
// ไม่บล็อกการใช้งาน — แค่เตือน + ให้กด "ส่งอีกครั้ง" ได้ ปิดได้ทันที (state
// อยู่แค่ระดับ widget เดียวนี้ ไม่ persist — เปิดหน้าใหม่จะเห็นอีกจนกว่าจะยืนยัน)
class EmailVerificationBanner extends StatefulWidget {
  const EmailVerificationBanner({super.key});
  @override
  State<EmailVerificationBanner> createState() => _EmailVerificationBannerState();
}

class _EmailVerificationBannerState extends State<EmailVerificationBanner> {
  bool _dismissed = false;
  bool _sending = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await user.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ส่งอีเมลยืนยันแล้ว กรุณาตรวจสอบกล่องจดหมาย (รวมถึงโฟลเดอร์สแปม)', style: GoogleFonts.notoSansThai()), backgroundColor: primaryGreen));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = e.code == 'too-many-requests'
            ? 'ส่งไปแล้วเมื่อครู่นี้ — รออีกสักครู่แล้วเช็คสแปมก่อนกดส่งซ้ำ'
            : 'ส่งไม่สำเร็จ (${e.code}) ลองใหม่ภายหลัง';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.notoSansThai()), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ส่งไม่สำเร็จ ลองใหม่ภายหลัง', style: GoogleFonts.notoSansThai()), backgroundColor: Colors.orange));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (_dismissed || user == null || user.emailVerified) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: kGapL),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(children: [
        Icon(Icons.mark_email_unread_rounded, color: Colors.amber.shade800, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('กรุณายืนยันอีเมลของคุณเพื่อความปลอดภัยของบัญชี (เช็คโฟลเดอร์สแปมด้วยถ้าไม่เจอ)', style: GoogleFonts.notoSansThai(fontSize: 12.5, color: Colors.amber.shade900, fontWeight: FontWeight.w600))),
        _sending
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
            : TextButton(onPressed: _resend, style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)), child: Text('ส่งอีกครั้ง', style: GoogleFonts.notoSansThai(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900))),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 16, color: Colors.amber.shade700),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => setState(() => _dismissed = true),
        ),
      ]),
    );
  }
}

Widget icon3D(IconData icon, List<Color> colors, double size) {
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
