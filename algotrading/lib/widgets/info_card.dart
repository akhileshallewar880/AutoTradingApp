import 'package:flutter/material.dart';

/// Professional, modern info/alert card widget
class InfoCard extends StatelessWidget {
  final String title;
  final String message;
  final InfoCardType type;
  final IconData? customIcon;
  final VoidCallback? onDismiss;
  final List<Widget>? actions;

  const InfoCard({
    super.key,
    required this.title,
    required this.message,
    this.type = InfoCardType.info,
    this.customIcon,
    this.onDismiss,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getColors();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors['background'],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors['border']!, width: 1),
        boxShadow: [
          BoxShadow(
            color: colors['shadow']!.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors['iconBg'],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  customIcon ?? _getIcon(),
                  color: colors['iconColor'],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Title and message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors['title'],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors['text'],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              if (onDismiss != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: colors['text'],
                  ),
                ),
              ],
            ],
          ),
          // Action buttons (if any)
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ...actions!.asMap().entries.map((e) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: e.key > 0 ? 8 : 0,
                    ),
                    child: e.value,
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _getIcon() {
    return switch (type) {
      InfoCardType.success => Icons.check_circle,
      InfoCardType.error => Icons.error,
      InfoCardType.warning => Icons.warning_amber_rounded,
      InfoCardType.info => Icons.info,
    };
  }

  Map<String, Color> _getColors() {
    return switch (type) {
      InfoCardType.success => {
        'background': Colors.green[50]!,
        'border': Colors.green[200]!,
        'shadow': Colors.green[600]!,
        'iconBg': Colors.green[100]!,
        'iconColor': Colors.green[700]!,
        'title': Colors.green[900]!,
        'text': Colors.green[800]!,
      },
      InfoCardType.error => {
        'background': Colors.red[50]!,
        'border': Colors.red[200]!,
        'shadow': Colors.red[600]!,
        'iconBg': Colors.red[100]!,
        'iconColor': Colors.red[700]!,
        'title': Colors.red[900]!,
        'text': Colors.red[800]!,
      },
      InfoCardType.warning => {
        'background': Colors.amber[50]!,
        'border': Colors.amber[200]!,
        'shadow': Colors.amber[600]!,
        'iconBg': Colors.amber[100]!,
        'iconColor': Colors.amber[700]!,
        'title': Colors.amber[900]!,
        'text': Colors.amber[800]!,
      },
      InfoCardType.info => {
        'background': Colors.blue[50]!,
        'border': Colors.blue[200]!,
        'shadow': Colors.blue[600]!,
        'iconBg': Colors.blue[100]!,
        'iconColor': Colors.blue[700]!,
        'title': Colors.blue[900]!,
        'text': Colors.blue[800]!,
      },
    };
  }
}

enum InfoCardType { info, success, warning, error }
