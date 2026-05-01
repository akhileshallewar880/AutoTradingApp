import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';

/// Animated price widget: counts up from old to new value on change.
/// Always renders in Space Grotesk mono. Color follows sign.
class PriceText extends StatefulWidget {
  const PriceText({
    super.key,
    required this.value,
    this.prefix = '₹',
    this.style,
    this.positiveColor,
    this.negativeColor,
    this.neutralColor,
    this.showSign = false,
    this.colorBySentiment = false,
    this.decimals = 2,
    this.duration = const Duration(milliseconds: 600),
  });

  final double value;
  final String prefix;
  final TextStyle? style;
  final Color? positiveColor;
  final Color? negativeColor;
  final Color? neutralColor;
  final bool showSign;

  /// If true, color is green for positive, red for negative.
  final bool colorBySentiment;
  final int decimals;
  final Duration duration;

  @override
  State<PriceText> createState() => _PriceTextState();
}

class _PriceTextState extends State<PriceText> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(begin: widget.value, end: widget.value).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(PriceText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = old.value;
      _anim = Tween<double>(begin: _from, end: widget.value).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final positiveColor = widget.positiveColor ?? vt.accentGreen;
    final negativeColor = widget.negativeColor ?? vt.danger;
    final neutralColor = widget.neutralColor ?? vt.textPrimary;

    Color color;
    if (widget.colorBySentiment) {
      color = widget.value > 0
          ? positiveColor
          : widget.value < 0
              ? negativeColor
              : neutralColor;
    } else {
      color = neutralColor;
    }

    final baseStyle = (widget.style ?? AppTextStyles.mono).copyWith(color: color);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        final sign = widget.showSign && v > 0 ? '+' : '';
        final formatted = '${widget.prefix}$sign${v.toStringAsFixed(widget.decimals)}';
        return Text(formatted, style: baseStyle);
      },
    );
  }
}

/// Compact colored P&L pill — e.g. "+₹1,234 (2.3%)".
class PnlPill extends StatelessWidget {
  const PnlPill({
    super.key,
    required this.pnl,
    required this.pnlPct,
    this.compact = false,
  });

  final double pnl;
  final double pnlPct;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isPos = pnl >= 0;
    final color = isPos ? context.vt.accentGreen : context.vt.danger;
    final bg = isPos ? context.vt.accentGreenDim : context.vt.dangerDim;
    final sign = isPos ? '+' : '';
    final label = compact
        ? '$sign${pnlPct.toStringAsFixed(1)}%'
        : '$sign₹${pnl.abs().toStringAsFixed(0)} ($sign${pnlPct.toStringAsFixed(1)}%)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTextStyles.monoSm.copyWith(color: color, fontSize: 12),
      ),
    );
  }
}
