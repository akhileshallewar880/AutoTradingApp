import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Consistent section header: bold H3 left + optional action link right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.actionLabel,
    this.trailing,
    this.paddingBottom = Sp.md,
    this.paddingTop = Sp.lg,
  });

  final String title;
  final VoidCallback? action;
  final String? actionLabel;
  final Widget? trailing;
  final double paddingBottom;
  final double paddingTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: paddingTop, bottom: paddingBottom),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.h3),
          Spacer(),
          ?trailing,
          if (action != null && actionLabel != null)
            GestureDetector(
              onTap: action,
              child: Text(
                actionLabel!,
                style: AppTextStyles.caption.copyWith(
                  color: context.vt.accentGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
