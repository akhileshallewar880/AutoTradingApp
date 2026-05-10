import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

/// Canonical VanTrade type system.
/// All font sizes use `.sp` so they scale proportionally on every screen size
/// (reference design: 390×844). Getters recompute on each build — safe because
/// ScreenUtil is always initialised before any widget builds.
abstract final class VtType {
  // ── Headings: Space Grotesk ───────────────────────────────────────────────

  static TextStyle get h1 => GoogleFonts.spaceGrotesk(
        fontSize: 22.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.25,
      );

  static TextStyle get h2 => GoogleFonts.spaceGrotesk(
        fontSize: 17.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle get h3 => GoogleFonts.spaceGrotesk(
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.4,
      );

  // ── Interface prose: Inter ────────────────────────────────────────────────

  static TextStyle get bodyLg => GoogleFonts.inter(
        fontSize: 15.sp,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.6,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14.sp,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.55,
      );

  static TextStyle get label => GoogleFonts.inter(
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.05,
        height: 1.4,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12.sp,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.45,
      );

  static TextStyle get micro => GoogleFonts.inter(
        fontSize: 11.sp,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        height: 1.5,
      );

  static TextStyle get statusLabel => GoogleFonts.inter(
        fontSize: 10.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        height: 1.2,
      );

  // ── Financial data: Space Grotesk (tabular figures) ─────────────────────

  static TextStyle get dataHero => GoogleFonts.spaceGrotesk(
        fontSize: 32.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.15,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get dataXL => GoogleFonts.spaceGrotesk(
        fontSize: 22.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get dataLG => GoogleFonts.spaceGrotesk(
        fontSize: 18.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get dataMD => GoogleFonts.spaceGrotesk(
        fontSize: 14.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.35,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get dataSM => GoogleFonts.spaceGrotesk(
        fontSize: 12.sp,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get dataXS => GoogleFonts.spaceGrotesk(
        fontSize: 11.sp,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
