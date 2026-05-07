import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tour_service.dart';

// ── Data model for a single tour step ────────────────────────────────────────

class VtTourStep {
  final GlobalKey targetKey;
  final String title;
  final String body;
  final EdgeInsets padding;
  final double radius;

  const VtTourStep({
    required this.targetKey,
    required this.title,
    required this.body,
    this.padding = const EdgeInsets.all(10),
    this.radius = 12.0,
  });
}

// ── Public API ────────────────────────────────────────────────────────────────

class VtTour {
  /// Shows the tour for [screenId] if never seen before.
  /// Call from initState via addPostFrameCallback.
  static Future<void> showIfNew({
    required BuildContext context,
    required String screenId,
    required List<VtTourStep> steps,
  }) async {
    final seen = await TourService.hasSeenTour(screenId);
    if (seen || !context.mounted || steps.isEmpty) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _VtTourOverlay(
        steps: steps,
        onDone: () {
          entry.remove();
          TourService.markTourSeen(screenId);
        },
      ),
    );
    Overlay.of(context).insert(entry);
  }
}

// ── Overlay StatefulWidget ────────────────────────────────────────────────────

class _VtTourOverlay extends StatefulWidget {
  final List<VtTourStep> steps;
  final VoidCallback onDone;

  const _VtTourOverlay({required this.steps, required this.onDone});

  @override
  State<_VtTourOverlay> createState() => _VtTourOverlayState();
}

class _VtTourOverlayState extends State<_VtTourOverlay>
    with TickerProviderStateMixin {
  int _step = 0;
  Rect? _hole;

  // Fade animation for step transitions
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // Pulse ring animation around spotlight
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    // Build the first hole after the overlay is inserted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _computeHole();
      _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _computeHole() {
    if (!mounted || _step >= widget.steps.length) return;
    final step = widget.steps[_step];
    final renderBox =
        step.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      setState(() => _hole = null);
      return;
    }
    final pos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final p = step.padding;
    setState(() {
      _hole = Rect.fromLTWH(
        pos.dx - p.left,
        pos.dy - p.top,
        size.width + p.left + p.right,
        size.height + p.top + p.bottom,
      );
    });
  }

  Future<void> _next() async {
    if (_step + 1 >= widget.steps.length) {
      await _fadeCtrl.reverse();
      widget.onDone();
      return;
    }
    await _fadeCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _step++;
      _hole = null; // clear while recomputing
    });
    // Wait a frame so the new state is rendered before computing bounds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _computeHole();
      if (mounted) _fadeCtrl.forward();
    });
  }

  Future<void> _skip() async {
    await _fadeCtrl.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    if (_step >= widget.steps.length) return const SizedBox.shrink();
    final currentStep = widget.steps[_step];
    final screenSize = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: Stack(
            children: [
              // ── Spotlight overlay ──────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (ctx, _) => CustomPaint(
                  size: screenSize,
                  painter: _SpotlightPainter(
                    hole: _hole,
                    borderRadius: currentStep.radius,
                    pulseProgress: _pulseAnim.value,
                  ),
                ),
              ),

              // ── Tooltip card ───────────────────────────────────────────────
              if (_hole != null)
                _positionedTooltip(context, _hole!, currentStep)
              else
                _centeredTooltip(context, currentStep),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionedTooltip(
      BuildContext context, Rect hole, VtTourStep step) {
    final size = MediaQuery.of(context).size;
    final spaceBelow = size.height - hole.bottom;
    final spaceAbove = hole.top;

    // Prefer below unless significantly more space above
    final goBelow = spaceBelow >= 220 || spaceBelow > spaceAbove;

    return Positioned(
      left: 16,
      right: 16,
      top: goBelow ? (hole.bottom + 12).clamp(0.0, size.height - 220) : null,
      bottom: !goBelow
          ? (size.height - hole.top + 12).clamp(0.0, size.height - 220)
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // absorb taps — prevent advancing via overlay GD
        child: _TourTooltip(
          step: _step,
          totalSteps: widget.steps.length,
          title: step.title,
          body: step.body,
          onNext: _next,
          onSkip: _skip,
        ),
      ),
    );
  }

  Widget _centeredTooltip(BuildContext context, VtTourStep step) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: _TourTooltip(
            step: _step,
            totalSteps: widget.steps.length,
            title: step.title,
            body: step.body,
            onNext: _next,
            onSkip: _skip,
          ),
        ),
      ),
    );
  }
}

// ── Spotlight painter ─────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final double borderRadius;
  final double pulseProgress;

  static const _overlayColor = Color(0xDC0B1120); // ~86% opacity dark navy

  const _SpotlightPainter({
    required this.hole,
    required this.borderRadius,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Layer needed for BlendMode.clear to work correctly
    canvas.saveLayer(Offset.zero & size, Paint());

    // Dark overlay
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _overlayColor,
    );

    if (hole != null) {
      // Punch a transparent hole in the overlay
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, Radius.circular(borderRadius)),
        Paint()..blendMode = BlendMode.clear,
      );
    }

    canvas.restore();

    if (hole != null) {
      // Animated purple pulse ring around the spotlight
      final expand = 4 + 8 * pulseProgress;
      final opacity = 0.55 - 0.40 * pulseProgress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          hole!.inflate(expand),
          Radius.circular(borderRadius + expand * 0.5),
        ),
        Paint()
          ..color = const Color(0xFF7B61FF).withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Subtle inner border on the spotlight to make it feel crisp
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, Radius.circular(borderRadius)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole ||
      old.pulseProgress != pulseProgress ||
      old.borderRadius != borderRadius;
}

// ── Tooltip card ──────────────────────────────────────────────────────────────

class _TourTooltip extends StatelessWidget {
  final int step;
  final int totalSteps;
  final String title;
  final String body;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourTooltip({
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.body,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7B61FF).withValues(alpha: 0.32),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B61FF).withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: step counter + skip ──────────────────────────────
          Row(
            children: [
              // Step counter badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B61FF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF7B61FF).withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 9,
                      color: Color(0xFF7B61FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${step + 1} of $totalSteps',
                      style: const TextStyle(
                        color: Color(0xFF7B61FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Skip button
              GestureDetector(
                onTap: onSkip,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Skip tour',
                    style: TextStyle(
                      color: Color(0xFF8B9BB4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Title ────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Text('✨', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF0F4FF),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          // ── Body ─────────────────────────────────────────────────────
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF9AA5BA),
              fontSize: 13,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 18),

          // ── Progress dots + Next button ───────────────────────────────
          Row(
            children: [
              // Progress dots
              ...List.generate(totalSteps, (i) {
                final active = i == step;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: active ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF00D4AA)
                        : const Color(0xFF2D3748),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
              const Spacer(),

              // Next / Done button
              GestureDetector(
                onTap: onNext,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D4AA), Color(0xFF0A9E6E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4AA).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLast ? 'Got it!' : 'Next',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 5),
                      isLast
                          ? const Text('🎉', style: TextStyle(fontSize: 13))
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 220.ms, curve: Curves.easeOut)
        .slideY(begin: 0.07, end: 0, duration: 220.ms, curve: Curves.easeOut);
  }
}
