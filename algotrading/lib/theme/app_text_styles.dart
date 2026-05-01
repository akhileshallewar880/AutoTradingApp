import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'vt_typography.dart';

/// Backward-compatible text style constants.
/// Interface font: Inter. Data font: IBM Plex Mono.
abstract final class AppTextStyles {
  // ── Interface: Inter ──────────────────────────────────────────────────────

  /// Large hero display — P&L totals. IBM Plex Mono.
  static final TextStyle display = VtType.dataHero;

  /// Screen titles.
  static final TextStyle h1 = VtType.h1;

  /// Section headers.
  static final TextStyle h2 = VtType.h2;

  /// Card headers, subsection labels.
  static final TextStyle h3 = VtType.h3;

  /// Standard body text.
  static final TextStyle body = VtType.body;

  /// Body text in secondary color — callers should override with context.vt.textSecondary.
  static final TextStyle bodySecondary = VtType.body;

  /// Labels, chips, button text.
  static final TextStyle label = VtType.label;

  /// Meta, timestamps, captions.
  static final TextStyle caption = VtType.caption;

  /// Footnotes, disclaimers.
  static final TextStyle micro = VtType.micro;

  /// Status words: OPEN, CLOSED, PENDING, BUY, SELL.
  static final TextStyle statusLabel = VtType.statusLabel;

  // ── Financial data: IBM Plex Mono ─────────────────────────────────────────

  /// All rupee values, prices, percentages.
  static final TextStyle mono = VtType.dataMD;

  /// Compact inline prices.
  static final TextStyle monoSm = VtType.dataSM;

  /// Large price displays.
  static final TextStyle monoLg = VtType.dataLG;

  /// Section-level totals.
  static final TextStyle monoXl = VtType.dataXL;

  // ── Legacy aliases (kept for backward compatibility) ─────────────────────
  // Screens that reference these continue to compile unchanged.

  static final TextStyle bodyLarge = VtType.bodyLg;

  static TextStyle get captionSecondary => caption;

  /// Heading alias — Inter 600.
  static final TextStyle headingBold = GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.3,
  );
}
