import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/vt_color_scheme.dart';

/// Universal card with ambient shadow + optional accent glow and tap ripple.
class VtCard extends StatelessWidget {
  const VtCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Sp.base),
    this.glowColor,
    this.gradient,
    this.onTap,
    this.borderColor,
    this.borderWidth = 1,
    this.radius = Rad.lg,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? glowColor;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double borderWidth;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;

    final shadows = [
      const BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 2)),
      if (glowColor != null)
        BoxShadow(
          color: glowColor!.withValues(alpha: 0.22),
          blurRadius: 18,
          spreadRadius: -2,
        ),
    ];

    final container = Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? vt.surface1) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : Border.all(color: vt.divider, width: 1),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return container;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: vt.accentGreen.withValues(alpha: 0.06),
        highlightColor: vt.accentGreen.withValues(alpha: 0.03),
        child: container,
      ),
    );
  }
}

/// Thin left-border accent card — used for position / holding rows.
class VtAccentCard extends StatelessWidget {
  const VtAccentCard({
    super.key,
    required this.child,
    required this.accentColor,
    this.padding = const EdgeInsets.all(Sp.base),
    this.onTap,
  });

  final Widget child;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VtCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(Rad.lg),
                  bottomLeft: Radius.circular(Rad.lg),
                ),
              ),
            ),
            Expanded(
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}
