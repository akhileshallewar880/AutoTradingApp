import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Full-screen immersive loading overlay for AI analysis.
/// Features: animated candlestick chart, orbiting particle system,
/// pulsing AI brain, cycling fun status messages, and a progress bar.
class AnimatedLoadingOverlay extends StatefulWidget {
  final String message;

  const AnimatedLoadingOverlay({
    super.key,
    this.message = 'Analyzing markets…',
  });

  @override
  State<AnimatedLoadingOverlay> createState() => _AnimatedLoadingOverlayState();
}

class _AnimatedLoadingOverlayState extends State<AnimatedLoadingOverlay>
    with TickerProviderStateMixin {
  // Controllers
  late AnimationController _orbitController;
  late AnimationController _pulseController;
  late AnimationController _textController;
  late AnimationController _candleController;
  late AnimationController _progressController;
  late AnimationController _glowController;
  late AnimationController _particleController;

  // Animations
  late Animation<double> _pulseAnim;
  late Animation<double> _textOpacity;
  late Animation<double> _glowAnim;

  // Messages cycling
  final List<Map<String, dynamic>> _steps = [
    {'icon': '📡', 'msg': 'Fetching live market data…', 'sub': 'Connecting to NSE feeds'},
    {'icon': '🔍', 'msg': 'Scanning 1,800+ stocks…', 'sub': 'Applying momentum filters'},
    {'icon': '🧠', 'msg': 'Running AI neural network…', 'sub': 'Deep learning in progress'},
    {'icon': '📊', 'msg': 'Calculating risk/reward…', 'sub': 'Optimising position sizes'},
    {'icon': '⚡', 'msg': 'Backtesting strategies…', 'sub': 'Simulating 5 years of data'},
    {'icon': '🎯', 'msg': 'Ranking opportunities…', 'sub': 'Sorting by alpha score'},
    {'icon': '✨', 'msg': 'Finalising picks…', 'sub': 'Almost ready for you!'},
  ];
  int _stepIndex = 0;

  // Candle data (random, regenerated each cycle)
  final _rng = math.Random();
  late List<_CandleData> _candles;

  @override
  void initState() {
    super.initState();

    _candles = _generateCandles(18);

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    _candleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..forward();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _textController.forward();
    _cycleSteps();
  }

  List<_CandleData> _generateCandles(int count) {
    double price = 100 + _rng.nextDouble() * 50;
    return List.generate(count, (i) {
      final change = (_rng.nextDouble() - 0.48) * 8;
      final open = price;
      price += change;
      final close = price;
      final high = math.max(open, close) + _rng.nextDouble() * 3;
      final low = math.min(open, close) - _rng.nextDouble() * 3;
      return _CandleData(open: open, close: close, high: high, low: low);
    });
  }

  void _cycleSteps() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 2800));
      if (!mounted) break;
      await _textController.reverse();
      if (!mounted) break;
      setState(() {
        _stepIndex = (_stepIndex + 1) % _steps.length;
        // Regenerate candles every 2 steps for live feel
        if (_stepIndex % 2 == 0) _candles = _generateCandles(18);
      });
      _textController.forward();
    }
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _pulseController.dispose();
    _textController.dispose();
    _candleController.dispose();
    _progressController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final step = _steps[_stepIndex];

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0E1A),
              Color(0xFF0D1F12),
              Color(0xFF0A1628),
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── Background particle field ──────────────────────────────
            AnimatedBuilder(
              animation: _particleController,
              builder: (_, __) => CustomPaint(
                size: size,
                painter: _ParticleFieldPainter(
                  progress: _particleController.value,
                  rng: _rng,
                ),
              ),
            ),

            // ── Animated candlestick chart (background) ────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: size.height * 0.32,
              child: AnimatedBuilder(
                animation: _candleController,
                builder: (_, __) => CustomPaint(
                  painter: _CandleChartPainter(
                    candles: _candles,
                    animValue: _candleController.value,
                  ),
                ),
              ),
            ),

            // ── Central content ────────────────────────────────────────
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Orbiting AI brain animation
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _orbitController,
                        _pulseController,
                        _glowController,
                      ]),
                      builder: (_, __) => CustomPaint(
                        painter: _AIBrainPainter(
                          orbit: _orbitController.value,
                          pulse: _pulseAnim.value,
                          glow: _glowAnim.value,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00BCD4)],
                    ).createShader(bounds),
                    child: const Text(
                      'AI ANALYSIS ENGINE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Powered by Deep Learning',
                    style: TextStyle(
                      color: Colors.green[300]!.withOpacity(0.7),
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Step icon + message
                  FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      children: [
                        Text(
                          step['icon'] as String,
                          style: const TextStyle(fontSize: 40),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          step['msg'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step['sub'] as String,
                          style: TextStyle(
                            color: Colors.green[300]!.withOpacity(0.8),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _progressController,
                          builder: (_, __) {
                            return Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: _progressController.value,
                                    minHeight: 6,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.1),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00E676),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Processing…',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '${(_progressController.value * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Step dots
                  _StepDots(
                    total: _steps.length,
                    current: _stepIndex,
                  ),
                ],
              ),
            ),

            // ── Top ticker strip ───────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TickerStrip(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model ───────────────────────────────────────────────────────────────
class _CandleData {
  final double open, close, high, low;
  const _CandleData(
      {required this.open,
      required this.close,
      required this.high,
      required this.low});
}

// ── AI Brain Painter ─────────────────────────────────────────────────────────
class _AIBrainPainter extends CustomPainter {
  final double orbit;
  final double pulse;
  final double glow;

  _AIBrainPainter(
      {required this.orbit, required this.pulse, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Outer glow ring
    final glowPaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.12 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.85, glowPaint);

    // Outer dashed orbit ring
    _drawDashedCircle(canvas, Offset(cx, cy), r * 0.88, 28,
        const Color(0xFF00E676).withOpacity(0.25), 2);

    // Mid orbit ring
    _drawDashedCircle(canvas, Offset(cx, cy), r * 0.62, 20,
        const Color(0xFF00BCD4).withOpacity(0.3), 1.5);

    // 5 outer orbiting particles
    for (int i = 0; i < 5; i++) {
      final angle = orbit * 2 * math.pi + i * 2 * math.pi / 5;
      final px = cx + r * 0.88 * math.cos(angle);
      final py = cy + r * 0.88 * math.sin(angle);
      final progress = i / 5;
      final dotPaint = Paint()
        ..color = Color.lerp(
          const Color(0xFF00E676),
          const Color(0xFF00BCD4),
          progress,
        )!
        ..style = PaintingStyle.fill;
      // Glow
      final dotGlow = Paint()
        ..color = dotPaint.color.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(px, py), 7, dotGlow);
      canvas.drawCircle(Offset(px, py), 5, dotPaint);
    }

    // 3 inner counter-rotating particles
    for (int i = 0; i < 3; i++) {
      final angle = -orbit * 2 * math.pi * 1.6 + i * 2 * math.pi / 3;
      final px = cx + r * 0.62 * math.cos(angle);
      final py = cy + r * 0.62 * math.sin(angle);
      final dotPaint = Paint()
        ..color = const Color(0xFFFFD740).withOpacity(0.9)
        ..style = PaintingStyle.fill;
      final dotGlow = Paint()
        ..color = const Color(0xFFFFD740).withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(px, py), 5, dotGlow);
      canvas.drawCircle(Offset(px, py), 3.5, dotPaint);
    }

    // Pulsing core
    final coreRadius = r * 0.30 * pulse;
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E676),
          const Color(0xFF00897B),
          const Color(0xFF004D40),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(cx, cy), radius: coreRadius));
    canvas.drawCircle(Offset(cx, cy), coreRadius, corePaint);

    // Core glow
    final coreGlow = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.25 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset(cx, cy), coreRadius * 1.4, coreGlow);

    // Candlestick bars in core
    final barPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final barHeights = [0.09, 0.14, 0.07, 0.12, 0.10];
    final spacing = r * 0.11;
    for (int i = 0; i < barHeights.length; i++) {
      final x = cx - spacing * 2 + spacing * i;
      final h = r * barHeights[i] * 2 * pulse;
      canvas.drawLine(Offset(x, cy - h), Offset(x, cy + h), barPaint);
    }

    // Connecting lines between outer dots (neural net look)
    final linePaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.15)
      ..strokeWidth = 1;
    for (int i = 0; i < 5; i++) {
      final a1 = orbit * 2 * math.pi + i * 2 * math.pi / 5;
      final a2 = orbit * 2 * math.pi + ((i + 2) % 5) * 2 * math.pi / 5;
      canvas.drawLine(
        Offset(cx + r * 0.88 * math.cos(a1), cy + r * 0.88 * math.sin(a1)),
        Offset(cx + r * 0.88 * math.cos(a2), cy + r * 0.88 * math.sin(a2)),
        linePaint,
      );
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius,
      int dashCount, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final dashAngle = 2 * math.pi / dashCount;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AIBrainPainter old) =>
      old.orbit != orbit || old.pulse != pulse || old.glow != glow;
}

// ── Candlestick Chart Painter ─────────────────────────────────────────────────
class _CandleChartPainter extends CustomPainter {
  final List<_CandleData> candles;
  final double animValue;

  _CandleChartPainter({required this.candles, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final allPrices = candles.expand((c) => [c.high, c.low]).toList();
    final minP = allPrices.reduce(math.min);
    final maxP = allPrices.reduce(math.max);
    final priceRange = maxP - minP;
    if (priceRange == 0) return;

    final candleWidth = size.width / (candles.length * 1.6);
    final gap = candleWidth * 0.6;

    // Draw area fill under the close line
    final closePath = Path();
    bool first = true;
    for (int i = 0; i < candles.length; i++) {
      final x = gap / 2 + i * (candleWidth + gap) + candleWidth / 2;
      final y = size.height -
          (candles[i].close - minP) / priceRange * size.height * 0.75 -
          size.height * 0.05;
      if (first) {
        closePath.moveTo(x, y);
        first = false;
      } else {
        closePath.lineTo(x, y);
      }
    }
    final lastX = gap / 2 +
        (candles.length - 1) * (candleWidth + gap) +
        candleWidth / 2;
    closePath.lineTo(lastX, size.height);
    closePath.lineTo(gap / 2, size.height);
    closePath.close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00E676).withOpacity(0.12),
          const Color(0xFF00E676).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(closePath, areaPaint);

    // Draw candles
    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = gap / 2 + i * (candleWidth + gap);
      final isBull = c.close >= c.open;

      // Animate: candles grow from bottom
      final revealProgress = ((animValue * candles.length) - i).clamp(0.0, 1.0);
      if (revealProgress == 0) continue;

      final yHigh = size.height -
          (c.high - minP) / priceRange * size.height * 0.75 -
          size.height * 0.05;
      final yLow = size.height -
          (c.low - minP) / priceRange * size.height * 0.75 -
          size.height * 0.05;
      final yOpen = size.height -
          (c.open - minP) / priceRange * size.height * 0.75 -
          size.height * 0.05;
      final yClose = size.height -
          (c.close - minP) / priceRange * size.height * 0.75 -
          size.height * 0.05;

      final color = isBull
          ? const Color(0xFF00E676).withOpacity(0.85)
          : const Color(0xFFFF5252).withOpacity(0.85);

      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      // Wick
      canvas.drawLine(
        Offset(x + candleWidth / 2, yHigh),
        Offset(x + candleWidth / 2, yLow),
        paint,
      );

      // Body
      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final bodyTop = math.min(yOpen, yClose);
      final bodyBottom = math.max(yOpen, yClose);
      final bodyH = math.max(bodyBottom - bodyTop, 2.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bodyTop, candleWidth, bodyH * revealProgress),
          const Radius.circular(1),
        ),
        bodyPaint,
      );
    }

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_CandleChartPainter old) =>
      old.animValue != animValue || old.candles != candles;
}

// ── Particle Field Painter ────────────────────────────────────────────────────
class _ParticleFieldPainter extends CustomPainter {
  final double progress;
  final math.Random rng;
  static final List<_Particle> _particles = [];

  _ParticleFieldPainter({required this.progress, required this.rng}) {
    if (_particles.isEmpty) {
      for (int i = 0; i < 60; i++) {
        _particles.add(_Particle(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          speed: 0.002 + rng.nextDouble() * 0.004,
          size: 1.0 + rng.nextDouble() * 2.5,
          opacity: 0.1 + rng.nextDouble() * 0.4,
          phase: rng.nextDouble(),
        ));
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final y = (p.y - progress * p.speed * 10) % 1.0;
      final twinkle = (math.sin((progress + p.phase) * 2 * math.pi) + 1) / 2;
      final paint = Paint()
        ..color = const Color(0xFF00E676)
            .withOpacity(p.opacity * (0.4 + 0.6 * twinkle));
      canvas.drawCircle(
        Offset(p.x * size.width, y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticleFieldPainter old) => old.progress != progress;
}

class _Particle {
  final double x, y, speed, size, opacity, phase;
  const _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.phase,
  });
}

// ── Step Dots ─────────────────────────────────────────────────────────────────
class _StepDots extends StatelessWidget {
  final int total;
  final int current;

  const _StepDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isActive = i == current;
        final isPast = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isActive
                ? const Color(0xFF00E676)
                : isPast
                    ? const Color(0xFF00E676).withOpacity(0.4)
                    : Colors.white.withOpacity(0.15),
          ),
        );
      }),
    );
  }
}

// ── Ticker Strip ──────────────────────────────────────────────────────────────
class _TickerStrip extends StatefulWidget {
  @override
  State<_TickerStrip> createState() => _TickerStripState();
}

class _TickerStripState extends State<_TickerStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _offset;

  static const _tickers = [
    ('RELIANCE', '+1.24%', true),
    ('TCS', '-0.38%', false),
    ('INFY', '+2.11%', true),
    ('HDFC', '+0.87%', true),
    ('ICICIBANK', '-0.52%', false),
    ('SBIN', '+3.04%', true),
    ('WIPRO', '+1.67%', true),
    ('BAJFINANCE', '-1.23%', false),
    ('HCLTECH', '+0.94%', true),
    ('AXISBANK', '+2.45%', true),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _offset = Tween<double>(begin: 0, end: -1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: Colors.black.withOpacity(0.4),
      child: AnimatedBuilder(
        animation: _offset,
        builder: (_, __) {
          return ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(
                    _offset.value * MediaQuery.of(context).size.width * 1.5,
                    0),
                child: Row(
                  children: [
                    ..._tickers,
                    ..._tickers,
                  ].map((t) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.$1,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            t.$2,
                            style: TextStyle(
                              color: t.$3
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFF5252),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 1,
                            height: 12,
                            color: Colors.white12,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
