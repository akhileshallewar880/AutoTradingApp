import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Canonical VanTrade type system.
/// Headings + financial data: Space Grotesk — geometric, precise, premium fintech feel.
/// Interface prose: Inter — optimal readability for body text and labels.
abstract final class VtType {
  // ── Headings: Space Grotesk ───────────────────────────────────────────────

  /// Screen titles. One per screen.
  static final TextStyle h1 = GoogleFonts.spaceGrotesk(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.25,
  );

  /// Section headers inside screens.
  static final TextStyle h2 = GoogleFonts.spaceGrotesk(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.3,
  );

  /// Card headers, subsection labels.
  static final TextStyle h3 = GoogleFonts.spaceGrotesk(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.4,
  );

  // ── Interface prose: Inter ────────────────────────────────────────────────

  /// Primary body text. Paragraphs and list items.
  static final TextStyle bodyLg = GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.6,
  );

  /// Standard body. Card content, descriptions.
  static final TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.55,
  );

  /// Labels, chips, tab text, button text.
  static final TextStyle label = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.05,
    height: 1.4,
  );

  /// Meta, timestamps, sub-labels.
  static final TextStyle caption = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.45,
  );

  /// Disclaimers, footnotes. Smallest readable size.
  static final TextStyle micro = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.5,
  );

  /// Status words only: OPEN, CLOSED, PENDING, BUY, SELL.
  static final TextStyle statusLabel = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    height: 1.2,
  );

  // ── Financial data: Space Grotesk (tabular figures) ───────────────────────
  // fontFeatures tabular figures ensures all digits are equal-width —
  // critical for aligning price columns and P&L values.

  /// Hero P&L display. One per screen maximum.
  static final TextStyle dataHero = GoogleFonts.spaceGrotesk(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    height: 1.15,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Section-level totals, portfolio value.
  static final TextStyle dataXL = GoogleFonts.spaceGrotesk(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    height: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Primary price display. Entry, LTP, NAV.
  static final TextStyle dataLG = GoogleFonts.spaceGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.3,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Standard table values.
  static final TextStyle dataMD = GoogleFonts.spaceGrotesk(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    height: 1.35,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Compact data. Chips, inline values, secondary prices.
  static final TextStyle dataSM = GoogleFonts.spaceGrotesk(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.4,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Timestamps in logs. Dense tables.
  static final TextStyle dataXS = GoogleFonts.spaceGrotesk(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.4,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
