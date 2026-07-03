import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ==========================================
// Theme & Colors
// ==========================================
const Color primaryGreen = Color(0xff186B44);
const Color lightGreen = Color(0xffE6F4EA);
const Color bgWhite = Color(0xffF7FCF9);
const Color textDark = Color(0xff2D312F);

// ===== Design tokens =====
const double kRadius = 16;
const double kCardPadding = 16;
const double kGapS = 8;
const double kGapM = 12;
const double kGapL = 16;
const double kGapXL = 24;
const Color textSecondary = Color(0xa62d312f); // textDark @ 65%

TextStyle tTitle([Color? c]) => GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: c ?? textDark);
TextStyle tBody([Color? c]) => GoogleFonts.notoSansThai(fontSize: 15, color: c ?? textDark);
TextStyle tCaption([Color? c]) => GoogleFonts.notoSansThai(fontSize: 14, color: c ?? textSecondary);
