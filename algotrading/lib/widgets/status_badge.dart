import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';

enum BadgeType { success, danger, warning, info, ai, neutral, gold }

/// Universal pill badge — colored bg + border + text.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.type = BadgeType.neutral,
    this.icon,
    this.dot = false,
    this.pulseDot = false,
  });

  final String label;
  final BadgeType type;
  final IconData? icon;
  final bool dot;
  final bool pulseDot;

  static (Color fg, Color bg, Color border) _colors(BadgeType t, BuildContext context) => switch (t) {
        BadgeType.success => (
            context.vt.accentGreen,
            context.vt.accentGreenDim,
            context.vt.accentGreen.withValues(alpha: 0.3)
          ),
        BadgeType.danger => (
            context.vt.danger,
            context.vt.dangerDim,
            context.vt.danger.withValues(alpha: 0.3)
          ),
        BadgeType.warning => (
            context.vt.warning,
            context.vt.warning.withValues(alpha: 0.10),
            context.vt.warning.withValues(alpha: 0.3)
          ),
        BadgeType.info => (
            const Color(0xFF60A5FA),
            const Color(0x1460A5FA),
            const Color(0x4060A5FA)
          ),
        BadgeType.ai => (
            context.vt.accentPurple,
            context.vt.accentPurpleDim,
            context.vt.accentPurple.withValues(alpha: 0.3)
          ),
        BadgeType.gold => (
            context.vt.accentGold,
            context.vt.accentGold.withValues(alpha: 0.12),
            context.vt.accentGold.withValues(alpha: 0.3)
          ),
        BadgeType.neutral => (
            context.vt.textSecondary,
            context.vt.surface2,
            context.vt.divider
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = _colors(type, context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot || pulseDot) ...[
            pulseDot ? _PulseDot(color: fg) : _Dot(color: fg),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: fg,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context2, child2) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
