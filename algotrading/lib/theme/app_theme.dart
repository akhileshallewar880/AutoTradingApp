import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'vt_colors.dart';
import 'vt_typography.dart';

import 'app_spacing.dart';
import 'vt_color_scheme.dart';

abstract final class AppTheme {
  // Legacy alias so existing `AppTheme.dark` references still compile.
  static ThemeData get dark => lightTheme;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // ── Scaffold ──────────────────────────────────────────────────────────
      scaffoldBackgroundColor: VtColors.bgBase,

      // ── Color scheme ──────────────────────────────────────────────────────
      colorScheme: const ColorScheme.light(
        brightness: Brightness.light,
        surface: VtColors.bgSurface,
        onSurface: VtColors.textPrimary,
        primary: VtColors.accent,
        onPrimary: Colors.white,
        secondary: VtColors.profit,
        onSecondary: Colors.white,
        error: VtColors.loss,
        onError: Colors.white,
        outline: VtColors.borderStrong,
        outlineVariant: VtColors.borderSubtle,
        surfaceContainerHighest: VtColors.bgRaised,
      ),

      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: VtColors.bgBase,
        foregroundColor: VtColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: const Color(0x18000000),
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: VtType.h1.copyWith(color: VtColors.textPrimary),
        iconTheme: const IconThemeData(color: VtColors.textSecondary, size: 22),
        actionsIconTheme: const IconThemeData(color: VtColors.textSecondary, size: 22),
      ),

      // ── Card ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: VtColors.bgSurface,
        elevation: 0,
        shadowColor: const Color(0x10000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: const BorderSide(color: VtColors.borderStrong, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── ElevatedButton ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VtColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: VtColors.bgRaised,
          disabledForegroundColor: VtColors.textTertiary,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
          textStyle: VtType.label,
          padding: const EdgeInsets.symmetric(horizontal: Sp.base),
        ),
      ),

      // ── OutlinedButton ────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: VtColors.textSecondary,
          disabledForegroundColor: VtColors.textTertiary,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          side: const BorderSide(color: VtColors.borderStrong, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
          textStyle: VtType.label,
          padding: const EdgeInsets.symmetric(horizontal: Sp.base),
        ),
      ),

      // ── TextButton ────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: VtColors.accent,
          textStyle: VtType.caption,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
      ),

      // ── Input ─────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VtColors.bgRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: const BorderSide(color: VtColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: const BorderSide(color: VtColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: const BorderSide(color: VtColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: const BorderSide(color: VtColors.loss),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: const BorderSide(color: VtColors.loss, width: 1.5),
        ),
        hintStyle: VtType.body.copyWith(color: VtColors.textTertiary),
        labelStyle: VtType.caption,
        errorStyle: VtType.caption.copyWith(color: VtColors.loss),
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: VtColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),

      // ── BottomSheet ───────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: VtColors.bgSurface,
        modalBackgroundColor: VtColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Rad.xl)),
          side: const BorderSide(color: VtColors.borderStrong),
        ),
      ),

      // ── Bottom navigation ─────────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: VtColors.bgSurface,
        selectedItemColor: VtColors.accent,
        unselectedItemColor: VtColors.textTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: false,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
      ),

      // ── NavigationBar (M3) ────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: VtColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: VtColors.accentSurface,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: VtColors.accent, size: 22);
          }
          return const IconThemeData(color: VtColors.textTertiary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: VtColors.accent);
          }
          return GoogleFonts.inter(fontSize: 12, color: VtColors.textTertiary);
        }),
        elevation: 0,
      ),

      // ── Chip ──────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: VtColors.bgRaised,
        selectedColor: VtColors.accentSurface,
        disabledColor: VtColors.bgOverlay,
        labelStyle: VtType.caption,
        side: const BorderSide(color: VtColors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      ),

      // ── Slider ────────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: VtColors.accent,
        inactiveTrackColor: VtColors.borderStrong,
        thumbColor: VtColors.accent,
        overlayColor: VtColors.accent.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        valueIndicatorColor: VtColors.bgOverlay,
        valueIndicatorTextStyle: VtType.dataSM,
      ),

      // ── Checkbox ──────────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return VtColors.accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: VtColors.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
      ),

      // ── Switch ────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : VtColors.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? VtColors.accent : VtColors.bgRaised),
        trackOutlineColor: WidgetStateProperty.all(VtColors.borderStrong),
      ),

      // ── TabBar ────────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: VtColors.accent,
        unselectedLabelColor: VtColors.textTertiary,
        indicatorColor: VtColors.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: VtColors.borderStrong,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
      ),

      // ── ProgressIndicator ─────────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: VtColors.accent,
        linearTrackColor: VtColors.borderStrong,
        circularTrackColor: VtColors.borderStrong,
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VtColors.bgSurface,
        contentTextStyle: VtType.body,
        actionTextColor: VtColors.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: const BorderSide(color: VtColors.borderStrong),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      // ── Dialog ────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: VtColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: const BorderSide(color: VtColors.borderStrong),
        ),
        titleTextStyle: VtType.h2,
        contentTextStyle: VtType.body.copyWith(color: VtColors.textSecondary),
      ),

      // ── ListTile ──────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: VtColors.textPrimary,
        iconColor: VtColors.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.xs),
      ),

      // ── Icon ──────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(color: VtColors.textSecondary, size: 22),

      // ── PopupMenu ─────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: VtColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: const Color(0x14000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: const BorderSide(color: VtColors.borderStrong),
        ),
        textStyle: VtType.body,
      ),

      // ── SegmentedButton ───────────────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return VtColors.accentSurface;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return VtColors.accent;
            return VtColors.textSecondary;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: VtColors.borderStrong)),
          textStyle: WidgetStateProperty.all(VtType.label),
          elevation: WidgetStateProperty.all(0),
        ),
      ),

      // ── ExpansionTile ─────────────────────────────────────────────────────
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: VtColors.bgSurface,
        collapsedBackgroundColor: VtColors.bgSurface,
        textColor: VtColors.textPrimary,
        collapsedTextColor: VtColors.textPrimary,
        iconColor: VtColors.textSecondary,
        collapsedIconColor: VtColors.textSecondary,
        tilePadding: const EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.xs),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      // ── Text ──────────────────────────────────────────────────────────────
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: VtColors.textPrimary,
        displayColor: VtColors.textPrimary,
      ),

      // ── Custom token extension ────────────────────────────────────────────
      extensions: const [VtColorScheme.light],
    );
  }

  // ── Dark theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const dk = VtColorScheme.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      scaffoldBackgroundColor: dk.surface0,

      colorScheme: ColorScheme.dark(
        brightness: Brightness.dark,
        surface: dk.surface1,
        onSurface: dk.textPrimary,
        primary: dk.accentGreen,
        onPrimary: Colors.black,
        secondary: dk.accentPurple,
        onSecondary: Colors.white,
        error: dk.danger,
        onError: Colors.white,
        outline: dk.divider,
        outlineVariant: dk.surface2,
        surfaceContainerHighest: dk.surface2,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: dk.surface0,
        foregroundColor: dk.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Colors.black26,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: VtType.h1.copyWith(color: dk.textPrimary),
        iconTheme: IconThemeData(color: dk.textSecondary, size: 22),
        actionsIconTheme: IconThemeData(color: dk.textSecondary, size: 22),
      ),

      cardTheme: CardThemeData(
        color: dk.surface1,
        elevation: 0,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: BorderSide(color: dk.divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: dk.accentGreen,
          foregroundColor: Colors.black,
          disabledBackgroundColor: dk.surface2,
          disabledForegroundColor: dk.textTertiary,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
          textStyle: VtType.label,
          padding: const EdgeInsets.symmetric(horizontal: Sp.base),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dk.textSecondary,
          disabledForegroundColor: dk.textTertiary,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          side: BorderSide(color: dk.divider, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
          textStyle: VtType.label,
          padding: const EdgeInsets.symmetric(horizontal: Sp.base),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dk.accentGreen,
          textStyle: VtType.caption,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dk.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: dk.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: dk.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: dk.accentGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: dk.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: dk.danger, width: 1.5),
        ),
        hintStyle: VtType.body.copyWith(color: dk.textTertiary),
        labelStyle: VtType.caption.copyWith(color: dk.textSecondary),
        errorStyle: VtType.caption.copyWith(color: dk.danger),
      ),

      dividerTheme: DividerThemeData(
        color: dk.divider,
        thickness: 1,
        space: 1,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dk.surface1,
        modalBackgroundColor: dk.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Rad.xl)),
          side: BorderSide(color: dk.divider),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: dk.surface1,
        selectedItemColor: dk.accentGreen,
        unselectedItemColor: dk.textTertiary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: false,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dk.surface1,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: dk.accentGreenDim,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: dk.accentGreen, size: 22);
          }
          return IconThemeData(color: dk.textTertiary, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: dk.accentGreen);
          }
          return GoogleFonts.inter(fontSize: 12, color: dk.textTertiary);
        }),
        elevation: 0,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: dk.surface2,
        selectedColor: dk.accentGreenDim,
        disabledColor: dk.surface3,
        labelStyle: VtType.caption.copyWith(color: dk.textPrimary),
        side: BorderSide(color: dk.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return dk.accentGreen;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.black),
        side: BorderSide(color: dk.divider, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.black : dk.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? dk.accentGreen : dk.surface2),
        trackOutlineColor: WidgetStateProperty.all(dk.divider),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: dk.accentGreen,
        unselectedLabelColor: dk.textTertiary,
        indicatorColor: dk.accentGreen,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: dk.divider,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dk.accentGreen,
        linearTrackColor: dk.surface2,
        circularTrackColor: dk.surface2,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: dk.surface2,
        contentTextStyle: VtType.body.copyWith(color: dk.textPrimary),
        actionTextColor: dk.accentGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(color: dk.divider),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: dk.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: BorderSide(color: dk.divider),
        ),
        titleTextStyle: VtType.h2.copyWith(color: dk.textPrimary),
        contentTextStyle: VtType.body.copyWith(color: dk.textSecondary),
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: dk.textPrimary,
        iconColor: dk.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.xs),
      ),

      iconTheme: IconThemeData(color: dk.textSecondary, size: 22),

      popupMenuTheme: PopupMenuThemeData(
        color: dk.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(color: dk.divider),
        ),
        textStyle: VtType.body.copyWith(color: dk.textPrimary),
      ),

      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: dk.surface1,
        collapsedBackgroundColor: dk.surface1,
        textColor: dk.textPrimary,
        collapsedTextColor: dk.textPrimary,
        iconColor: dk.textSecondary,
        collapsedIconColor: dk.textSecondary,
        tilePadding: const EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.xs),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: dk.textPrimary,
        displayColor: dk.textPrimary,
      ),

      extensions: const [VtColorScheme.dark],
    );
  }
}
