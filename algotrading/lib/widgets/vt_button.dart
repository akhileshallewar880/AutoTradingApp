import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/vt_color_scheme.dart';

enum VtButtonVariant { primary, secondary, ghost, danger }

/// Premium button with press-scale feedback and built-in loading state.
class VtButton extends StatefulWidget {
  const VtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = VtButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.height = 56,
    this.width = double.infinity,
    this.radius = Rad.md,
    this.fontSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final VtButtonVariant variant;
  final Widget? icon;
  final bool loading;
  final double height;
  final double width;
  final double radius;
  final double? fontSize;

  @override
  State<VtButton> createState() => _VtButtonState();
}

class _VtButtonState extends State<VtButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final isDisabled = widget.onPressed == null || widget.loading;

    final Color bgColor;
    final Color fgColor;
    final Color? borderColor;
    switch (widget.variant) {
      case VtButtonVariant.primary:
        bgColor = vt.accentPurple; fgColor = Colors.white; borderColor = null;
      case VtButtonVariant.secondary:
        bgColor = vt.surface2; fgColor = vt.textPrimary; borderColor = vt.divider;
      case VtButtonVariant.ghost:
        bgColor = Colors.transparent; fgColor = vt.textSecondary; borderColor = null;
      case VtButtonVariant.danger:
        bgColor = vt.danger; fgColor = Colors.white; borderColor = null;
    }

    final effectiveBg = isDisabled
        ? (widget.variant == VtButtonVariant.primary
            ? vt.accentPurple.withValues(alpha: 0.3)
            : vt.surface2)
        : bgColor;

    final content = widget.loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                widget.icon!,
                const SizedBox(width: Sp.sm),
              ],
              Text(
                widget.label,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDisabled ? fgColor.withValues(alpha: 0.5) : fgColor,
                  fontSize: widget.fontSize,
                ),
              ),
            ],
          );

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: isDisabled ? null : (_) {
        setState(() => _pressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: effectiveBg,
            borderRadius: BorderRadius.circular(widget.radius),
            border: borderColor != null
                ? Border.all(color: borderColor, width: 1.5)
                : null,
            boxShadow: (!isDisabled && widget.variant == VtButtonVariant.primary)
                ? [
                    BoxShadow(
                      color: vt.accentPurple.withValues(alpha: _pressed ? 0.12 : 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}
