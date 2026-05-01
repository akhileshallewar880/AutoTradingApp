import 'package:flutter/material.dart';

/// Canonical VanTrade color tokens — Premium Light theme.
abstract final class VtColors {
  // ── Background layer ──────────────────────────────────────────────────────
  static const Color bgBase    = Color(0xFFF4F6FA); // scaffold — cool off-white
  static const Color bgSurface = Color(0xFFFFFFFF); // cards — crisp white
  static const Color bgRaised  = Color(0xFFEDF0F7); // inputs, secondary surface
  static const Color bgOverlay = Color(0xFFE4E9F3); // modals, sheets

  // ── Border layer ──────────────────────────────────────────────────────────
  static const Color borderStrong = Color(0xFFD8DFEC); // standard borders
  static const Color borderSubtle = Color(0xFFEDF0F7); // dividers

  // ── Text layer ────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF0D1421); // near-black, slight blue
  static const Color textSecondary = Color(0xFF536080); // muted blue-gray
  static const Color textTertiary  = Color(0xFF8E9BB5); // placeholder / disabled

  // ── Functional: profit / loss ─────────────────────────────────────────────
  static const Color profit        = Color(0xFF0A9E6E); // deep emerald
  static const Color profitSurface = Color(0xFFE7F7F3); // emerald tint bg

  static const Color loss          = Color(0xFFD63848); // clean red
  static const Color lossSurface   = Color(0xFFFCEEF0); // red tint bg

  // ── Structural accent — deep indigo (AI + primary CTA) ───────────────────
  static const Color accent        = Color(0xFF4F46E5); // deep indigo
  static const Color accentSurface = Color(0xFFEEECFD); // indigo tint bg
  static const Color accentHover   = Color(0xFF4338CA); // darker indigo

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color warning        = Color(0xFFD97706); // deep amber
  static const Color warningSurface = Color(0xFFFEF3E2); // amber tint bg
  static const Color neutral        = Color(0xFF6B7A99); // blue-gray
  static const Color neutralSurface = Color(0xFFEDF0F7); // neutral bg

  // ── Scrim ─────────────────────────────────────────────────────────────────
  static const Color scrim = Color(0x66000000); // 40% black
}
