import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:healthcare_app/core/theme.dart';

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
