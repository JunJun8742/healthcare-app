import 'package:flutter/material.dart';
import 'package:healthcare_app/core/theme.dart';

abstract final class QueueStatus {
  static const waiting = 'กำลังรอ';
  static const called = 'เรียกคิว';
  static const treating = 'กำลังรักษา';
  static const done = 'เสร็จสิ้น';
  static const cancelled = 'ยกเลิก';
  static const active = [waiting, called, treating];
  static const terminal = [done, cancelled];
}

abstract final class SosStatus {
  static const pending = 'รอรับเรื่อง';
  static const resolved = 'รับเรื่องแล้ว';
}

// ===== สถานะคิว: สี/ไอคอน/ป้ายชื่อ ใช้ร่วมกันทุกหน้า =====
({Color color, IconData icon, String label}) statusInfo(String status) {
  switch (status) {
    case 'กำลังรอ':
      return (color: const Color(0xffB7791F), icon: Icons.hourglass_top_rounded, label: 'กำลังรอ');
    case 'เรียกคิว':
      return (color: const Color(0xff1D4ED8), icon: Icons.campaign_rounded, label: 'เรียกคิว');
    case 'กำลังรักษา':
      return (color: primaryGreen, icon: Icons.healing_rounded, label: 'กำลังรักษา');
    case 'เสร็จสิ้น':
      return (color: const Color(0xff4B6358), icon: Icons.check_circle_rounded, label: 'เสร็จสิ้น');
    case 'ยกเลิก':
      return (color: const Color(0xffB91C1C), icon: Icons.cancel_rounded, label: 'ยกเลิก');
    default:
      return (color: textSecondary, icon: Icons.help_outline_rounded, label: status);
  }
}
