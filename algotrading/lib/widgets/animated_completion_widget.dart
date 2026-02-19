import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A stat item to display below the completion animation.
class CompletionStatItem {
  final String label;
  final String value;
  final Color? color;
  const CompletionStatItem(this.label, this.value, {this.color});
}

/// Animated completion widget shown when order execution finishes.
/// Shows an animated checkmark for success or animated X for failure.
class AnimatedCompletionWidget extends StatefulWidget {
  final bool isSuccess;
  final String title;
  final String subtitle;
  final List<CompletionStatItem> stats;

  const AnimatedCompletionWidget({
    super.key,
    required this.isSuccess,
    required this.title,
    required this.subtitle,
    this.stats = const <CompletionStatItem>[],
  });

  @override
  State<AnimatedCompletionWidget> createState() =>
      _AnimatedCompletionWidgetState();
}


class _AnimatedCompletionWidgetState extends State<AnimatedCompletionWidget>
    with TickerProviderStateMixin {
  late AnimationController _circleController;
  late AnimationController _iconController;
  late AnimationController _statsController;
  late Animation<double> _circleProgress;
  late Animation<double> _iconProgress;
  late Animation<double> _statsOpacity;
  late Animation<Offset> _statsSlide;

  @override
  void initState() {
    super.initState();

    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _circleProgress = CurvedAnimation(
      parent: _circleController,
      curve: Curves.easeOut,
    );

    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _iconProgress = CurvedAnimation(
      parent: _iconController,
      curve: Curves.elasticOut,
    );

    _statsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _statsOpacity = CurvedAnimation(
      parent: _statsController,
      curve: Curves.easeIn,
    );
    _statsSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _statsController, curve: Curves.easeOut));

    // Sequence the animations
    _circleController.forward().then((_) {
      _iconController.forward().then((_) {
        _statsController.forward();
      });
    });
  }

  @override
  void dispose() {
    _circleController.dispose();
    _iconController.dispose();
    _statsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSuccess ? Colors.green[700]! : Colors.red[600]!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated circle + icon
        SizedBox(
          width: 120,
          height: 120,
          child: AnimatedBuilder(
            animation: Listenable.merge([_circleProgress, _iconProgress]),
            builder: (context, _) {
              return CustomPaint(
                painter: _CompletionPainter(
                  progress: _circleProgress.value,
                  iconProgress: _iconProgress.value,
                  isSuccess: widget.isSuccess,
                  color: color,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        // Title
        FadeTransition(
          opacity: _statsOpacity,
          child: SlideTransition(
            position: _statsSlide,
            child: Column(
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.stats.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildStatsRow(widget.stats),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(List<CompletionStatItem> stats) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: stats.map((s) {
        return Column(
          children: [
            Text(
              s.value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: s.color ?? Colors.black87,
              ),
            ),
            Text(
              s.label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _CompletionPainter extends CustomPainter {
  final double progress;
  final double iconProgress;
  final bool isSuccess;
  final Color color;

  _CompletionPainter({
    required this.progress,
    required this.iconProgress,
    required this.isSuccess,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Background circle (light)
    final bgPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Animated arc border
    final arcPaint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );

    if (iconProgress > 0) {
      final iconPaint = Paint()
        ..color = color
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (isSuccess) {
        // Animated checkmark
        final path = Path();
        final p1 = Offset(center.dx - radius * 0.35, center.dy);
        final p2 = Offset(center.dx - radius * 0.05, center.dy + radius * 0.3);
        final p3 = Offset(center.dx + radius * 0.4, center.dy - radius * 0.25);

        // Draw first segment
        if (iconProgress < 0.5) {
          final t = iconProgress / 0.5;
          path.moveTo(p1.dx, p1.dy);
          path.lineTo(
            p1.dx + (p2.dx - p1.dx) * t,
            p1.dy + (p2.dy - p1.dy) * t,
          );
        } else {
          final t = (iconProgress - 0.5) / 0.5;
          path.moveTo(p1.dx, p1.dy);
          path.lineTo(p2.dx, p2.dy);
          path.lineTo(
            p2.dx + (p3.dx - p2.dx) * t,
            p2.dy + (p3.dy - p2.dy) * t,
          );
        }
        canvas.drawPath(path, iconPaint);
      } else {
        // Animated X
        final half = radius * 0.35 * iconProgress;
        canvas.drawLine(
          Offset(center.dx - half, center.dy - half),
          Offset(center.dx + half, center.dy + half),
          iconPaint,
        );
        canvas.drawLine(
          Offset(center.dx + half, center.dy - half),
          Offset(center.dx - half, center.dy + half),
          iconPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CompletionPainter old) =>
      old.progress != progress || old.iconProgress != iconProgress;
}

/// Convenience factory constructors
extension AnimatedCompletionWidgetFactory on AnimatedCompletionWidget {
  static AnimatedCompletionWidget success({
    String title = 'Orders Placed!',
    String subtitle = 'All trades have been executed successfully.',
    int completed = 0,
    int failed = 0,
  }) {
    return AnimatedCompletionWidget(
      isSuccess: true,
      title: title,
      subtitle: subtitle,
      stats: [
        CompletionStatItem('Completed', '$completed', color: Colors.green[700]),
        CompletionStatItem('Failed', '$failed', color: Colors.red[600]),
      ],
    );
  }

  static AnimatedCompletionWidget failure({
    String title = 'Execution Failed',
    String subtitle = 'Some orders could not be placed. Please try again.',
    int completed = 0,
    int failed = 0,
  }) {
    return AnimatedCompletionWidget(
      isSuccess: false,
      title: title,
      subtitle: subtitle,
      stats: [
        CompletionStatItem('Completed', '$completed', color: Colors.green[700]),
        CompletionStatItem('Failed', '$failed', color: Colors.red[600]),
      ],
    );
  }
}
