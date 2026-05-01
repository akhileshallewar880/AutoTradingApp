import 'package:flutter/material.dart';
import 'vt_colors.dart';

// ignore_for_file: non_constant_identifier_names

/// Backward-compatible color constants — Premium Light theme.
/// All values map to the VtColors canonical token system.
abstract final class AppColors {
  // ── Backgrounds ───────────────────────────────────────────────────────────
  static const Color surface0 = VtColors.bgBase;      // scaffold
  static const Color surface1 = VtColors.bgSurface;   // cards
  static const Color surface2 = VtColors.bgRaised;    // inputs, hover
  static const Color surface3 = VtColors.bgOverlay;   // modals, sheets

  // ── Borders ───────────────────────────────────────────────────────────────
  static const Color divider = VtColors.borderStrong;

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary   = VtColors.textPrimary;
  static const Color textSecondary = VtColors.textSecondary;
  static const Color textTertiary  = VtColors.textTertiary;

  // ── Profit ────────────────────────────────────────────────────────────────
  static const Color accentGreen    = VtColors.profit;
  static const Color accentGreenDim = VtColors.profitSurface;

  // ── Structural accent (CTA, AI, focus, active state) ─────────────────────
  static const Color accentPurple    = VtColors.accent;
  static const Color accentPurpleDim = VtColors.accentSurface;

  // ── Achievement / streak — deep amber ────────────────────────────────────
  static const Color accentGold = VtColors.warning;

  // ── Loss / Danger ─────────────────────────────────────────────────────────
  static const Color danger    = VtColors.loss;
  static const Color dangerDim = VtColors.lossSurface;

  // ── Warning ───────────────────────────────────────────────────────────────
  static const Color warning = VtColors.warning;

  // ── Overlay scrim ─────────────────────────────────────────────────────────
  static const Color overlayScrim = VtColors.scrim;

  // ── Neutral ───────────────────────────────────────────────────────────────
  static const Color neutral = VtColors.neutral;

  // ── Shadows — crisp elevation, no colour glows on light bg ───────────────
  static List<BoxShadow> get ambientShadow => const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 12,
          offset: Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get greenGlow => [
        BoxShadow(
          color: VtColors.profit.withValues(alpha: 0.14),
          blurRadius: 16,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];

  static List<BoxShadow> get dangerGlow => [
        BoxShadow(
          color: VtColors.loss.withValues(alpha: 0.14),
          blurRadius: 16,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];

  static List<BoxShadow> get purpleGlow => [
        BoxShadow(
          color: VtColors.accent.withValues(alpha: 0.14),
          blurRadius: 16,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];
}
