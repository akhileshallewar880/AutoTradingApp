import 'package:flutter/material.dart';

/// Market-standard VanTrade logo widget.
/// Uses a deep green gradient container with a custom candlestick chart icon
/// that matches the app's primary green theme.
class VanTradeLogoWidget extends StatelessWidget {
  final double size;

  const VanTradeLogoWidget({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.22;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.40),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.09),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: CustomPaint(
          painter: _CandlestickPainter(),
        ),
      ),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Bright (bullish) paints
    final brightBody = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final brightWick = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Dim (bearish) paints
    final dimBody = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;

    final dimWick = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Candle 1 – leftmost, dim/short
    _drawCandle(
      canvas,
      wickPaint: dimWick,
      bodyPaint: dimBody,
      cx: w * 0.20,
      candleW: w * 0.13,
      wickTop: h * 0.22,
      bodyTop: h * 0.32,
      bodyBottom: h * 0.66,
      wickBottom: h * 0.76,
    );

    // Candle 2 – middle, dim/medium
    _drawCandle(
      canvas,
      wickPaint: dimWick,
      bodyPaint: dimBody,
      cx: w * 0.50,
      candleW: w * 0.13,
      wickTop: h * 0.14,
      bodyTop: h * 0.24,
      bodyBottom: h * 0.62,
      wickBottom: h * 0.74,
    );

    // Candle 3 – rightmost, bright/tall (bullish)
    _drawCandle(
      canvas,
      wickPaint: brightWick,
      bodyPaint: brightBody,
      cx: w * 0.80,
      candleW: w * 0.15,
      wickTop: h * 0.04,
      bodyTop: h * 0.12,
      bodyBottom: h * 0.80,
      wickBottom: h * 0.90,
    );
  }

  void _drawCandle(
    Canvas canvas, {
    required Paint wickPaint,
    required Paint bodyPaint,
    required double cx,
    required double candleW,
    required double wickTop,
    required double bodyTop,
    required double bodyBottom,
    required double wickBottom,
  }) {
    // Upper wick
    canvas.drawLine(Offset(cx, wickTop), Offset(cx, bodyTop), wickPaint);
    // Lower wick
    canvas.drawLine(Offset(cx, bodyBottom), Offset(cx, wickBottom), wickPaint);
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
            cx - candleW / 2, bodyTop, cx + candleW / 2, bodyBottom),
        const Radius.circular(2.5),
      ),
      bodyPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
