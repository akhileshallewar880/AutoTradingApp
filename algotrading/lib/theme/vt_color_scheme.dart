import 'package:flutter/material.dart';

/// All custom VanTrade color tokens as a ThemeExtension.
/// Register in both lightTheme and darkTheme, then access via
/// `VtColorScheme.of(context)` or the `context.vt` shorthand.
@immutable
class VtColorScheme extends ThemeExtension<VtColorScheme> {
  const VtColorScheme({
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.accentGreen,
    required this.accentGreenDim,
    required this.accentPurple,
    required this.accentPurpleDim,
    required this.accentGold,
    required this.danger,
    required this.dangerDim,
    required this.warning,
    required this.warningDim,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.overlayScrim,
    required this.neutral,
    required this.isDark,
  });

  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color accentGreen;
  final Color accentGreenDim;
  final Color accentPurple;
  final Color accentPurpleDim;
  final Color accentGold;
  final Color danger;
  final Color dangerDim;
  final Color warning;
  final Color warningDim;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color overlayScrim;
  final Color neutral;
  final bool isDark;

  // ── Light palette ─────────────────────────────────────────────────────────
  static const light = VtColorScheme(
    surface0:       Color(0xFFF4F6FA),
    surface1:       Color(0xFFFFFFFF),
    surface2:       Color(0xFFEDF0F7),
    surface3:       Color(0xFFE4E9F3),
    accentGreen:    Color(0xFF0A9E6E),
    accentGreenDim: Color(0xFFE7F7F3),
    accentPurple:   Color(0xFF4F46E5),
    accentPurpleDim:Color(0xFFEEECFD),
    accentGold:     Color(0xFFD97706),
    danger:         Color(0xFFD63848),
    dangerDim:      Color(0xFFFCEEF0),
    warning:        Color(0xFFD97706),
    warningDim:     Color(0xFFFEF3E2),
    textPrimary:    Color(0xFF0D1421),
    textSecondary:  Color(0xFF536080),
    textTertiary:   Color(0xFF8E9BB5),
    divider:        Color(0xFFD8DFEC),
    overlayScrim:   Color(0x66000000),
    neutral:        Color(0xFF6B7A99),
    isDark:         false,
  );

  // ── Dark palette — Deep Intelligence ──────────────────────────────────────
  static const dark = VtColorScheme(
    surface0:       Color(0xFF0B1120),
    surface1:       Color(0xFF131C2E),
    surface2:       Color(0xFF1C2840),
    surface3:       Color(0xFF243150),
    accentGreen:    Color(0xFF00D4AA),
    accentGreenDim: Color(0x1A00D4AA),
    accentPurple:   Color(0xFF7B61FF),
    accentPurpleDim:Color(0x1A7B61FF),
    accentGold:     Color(0xFFFFB800),
    danger:         Color(0xFFFF4757),
    dangerDim:      Color(0x14FF4757),
    warning:        Color(0xFFFF9F43),
    warningDim:     Color(0x14FF9F43),
    textPrimary:    Color(0xFFF0F4FF),
    textSecondary:  Color(0xFF8B9BB4),
    textTertiary:   Color(0xFF4A5568),
    divider:        Color(0xFF1E2D45),
    overlayScrim:   Color(0xCC000000),
    neutral:        Color(0xFF4A5568),
    isDark:         true,
  );

  static VtColorScheme of(BuildContext context) =>
      Theme.of(context).extension<VtColorScheme>() ?? light;

  // ── ThemeExtension boilerplate ────────────────────────────────────────────

  @override
  VtColorScheme copyWith({
    Color? surface0, Color? surface1, Color? surface2, Color? surface3,
    Color? accentGreen, Color? accentGreenDim,
    Color? accentPurple, Color? accentPurpleDim,
    Color? accentGold, Color? danger, Color? dangerDim,
    Color? warning, Color? warningDim,
    Color? textPrimary, Color? textSecondary, Color? textTertiary,
    Color? divider, Color? overlayScrim, Color? neutral, bool? isDark,
  }) => VtColorScheme(
    surface0:        surface0        ?? this.surface0,
    surface1:        surface1        ?? this.surface1,
    surface2:        surface2        ?? this.surface2,
    surface3:        surface3        ?? this.surface3,
    accentGreen:     accentGreen     ?? this.accentGreen,
    accentGreenDim:  accentGreenDim  ?? this.accentGreenDim,
    accentPurple:    accentPurple    ?? this.accentPurple,
    accentPurpleDim: accentPurpleDim ?? this.accentPurpleDim,
    accentGold:      accentGold      ?? this.accentGold,
    danger:          danger          ?? this.danger,
    dangerDim:       dangerDim       ?? this.dangerDim,
    warning:         warning         ?? this.warning,
    warningDim:      warningDim      ?? this.warningDim,
    textPrimary:     textPrimary     ?? this.textPrimary,
    textSecondary:   textSecondary   ?? this.textSecondary,
    textTertiary:    textTertiary    ?? this.textTertiary,
    divider:         divider         ?? this.divider,
    overlayScrim:    overlayScrim    ?? this.overlayScrim,
    neutral:         neutral         ?? this.neutral,
    isDark:          isDark          ?? this.isDark,
  );

  @override
  VtColorScheme lerp(VtColorScheme? other, double t) {
    if (other == null) return this;
    return VtColorScheme(
      surface0:        Color.lerp(surface0,        other.surface0,        t)!,
      surface1:        Color.lerp(surface1,        other.surface1,        t)!,
      surface2:        Color.lerp(surface2,        other.surface2,        t)!,
      surface3:        Color.lerp(surface3,        other.surface3,        t)!,
      accentGreen:     Color.lerp(accentGreen,     other.accentGreen,     t)!,
      accentGreenDim:  Color.lerp(accentGreenDim,  other.accentGreenDim,  t)!,
      accentPurple:    Color.lerp(accentPurple,    other.accentPurple,    t)!,
      accentPurpleDim: Color.lerp(accentPurpleDim, other.accentPurpleDim, t)!,
      accentGold:      Color.lerp(accentGold,      other.accentGold,      t)!,
      danger:          Color.lerp(danger,          other.danger,          t)!,
      dangerDim:       Color.lerp(dangerDim,        other.dangerDim,       t)!,
      warning:         Color.lerp(warning,         other.warning,         t)!,
      warningDim:      Color.lerp(warningDim,       other.warningDim,      t)!,
      textPrimary:     Color.lerp(textPrimary,     other.textPrimary,     t)!,
      textSecondary:   Color.lerp(textSecondary,   other.textSecondary,   t)!,
      textTertiary:    Color.lerp(textTertiary,    other.textTertiary,    t)!,
      divider:         Color.lerp(divider,         other.divider,         t)!,
      overlayScrim:    Color.lerp(overlayScrim,    other.overlayScrim,    t)!,
      neutral:         Color.lerp(neutral,         other.neutral,         t)!,
      isDark:          t > 0.5 ? other.isDark : isDark,
    );
  }
}

/// Convenience shorthand. Usage: `context.vt.surface0`
extension VtColorSchemeX on BuildContext {
  VtColorScheme get vt => VtColorScheme.of(this);
}
