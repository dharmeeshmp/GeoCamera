import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Live Accelerometer Bubble Level & Tilt Horizon indicator overlay.
///
/// Features:
/// 1. Top-Down Flat-Lay Mode (z.abs() > 8.5):
///    Center target ring + dynamic bubble dot with 'FLAT' badge when level within ~2°.
/// 2. Upright Horizon Tilt Mode (z.abs() <= 8.5):
///    Center horizon bar with reference ticks that snaps to green when within ±1.5°.
///
/// Wrapped in IgnorePointer so gestures pass straight through to the camera viewfinder.
class HorizonLevelOverlay extends StatefulWidget {
  final bool enabled;

  const HorizonLevelOverlay({
    super.key,
    required this.enabled,
  });

  @override
  State<HorizonLevelOverlay> createState() => _HorizonLevelOverlayState();
}

class _HorizonLevelOverlayState extends State<HorizonLevelOverlay> {
  StreamSubscription<AccelerometerEvent>? _subscription;

  double _smoothX = 0.0;
  double _smoothY = 9.8;
  double _smoothZ = 0.0;
  static const double _alpha = 0.2;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _startListening();
    }
  }

  @override
  void didUpdateWidget(covariant HorizonLevelOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _startListening();
      } else {
        _stopListening();
      }
    }
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      if (!mounted) return;
      setState(() {
        _smoothX = _smoothX + _alpha * (event.x - _smoothX);
        _smoothY = _smoothY + _alpha * (event.y - _smoothY);
        _smoothZ = _smoothZ + _alpha * (event.z - _smoothZ);
      });
    });
  }

  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _HorizonLevelPainter(
          x: _smoothX,
          y: _smoothY,
          z: _smoothZ,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HorizonLevelPainter extends CustomPainter {
  final double x;
  final double y;
  final double z;

  _HorizonLevelPainter({
    required this.x,
    required this.y,
    required this.z,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ==========================================================
    // 1. TOP-DOWN FLAT-LAY MODE (|z| > 8.5 m/s²)
    // ==========================================================
    if (z.abs() > 8.5) {
      final bool isFlat = x.abs() < 0.35 && y.abs() < 0.35;

      // Fixed center target ring (radius: 22)
      final ringShadow = Paint()
        ..color = Colors.black26
        ..strokeWidth = isFlat ? 3.0 : 2.2
        ..style = PaintingStyle.stroke;

      final ringPaint = Paint()
        ..color = isFlat ? Colors.greenAccent : Colors.white.withOpacity(0.40)
        ..strokeWidth = isFlat ? 2.2 : 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, 22, ringShadow);
      canvas.drawCircle(center, 22, ringPaint);

      // Moving bubble dot (radius: 8) offset by (x * 4.5, -y * 4.5) clamped within 32px
      final double dx = (x * 4.5).clamp(-32.0, 32.0);
      final double dy = (-y * 4.5).clamp(-32.0, 32.0);
      final bubbleCenter = center + Offset(dx, dy);

      final bubbleShadow = Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.fill;

      final bubblePaint = Paint()
        ..color = isFlat ? Colors.greenAccent : Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(bubbleCenter, 9, bubbleShadow);
      canvas.drawCircle(bubbleCenter, 8, bubblePaint);

      // Subtle 'FLAT' pill badge below the ring
      if (isFlat) {
        final badgeRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + const Offset(0, 42), width: 48, height: 18),
          const Radius.circular(9),
        );
        final bgPaint = Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.fill;
        canvas.drawRRect(badgeRRect, bgPaint);

        final textSpan = const TextSpan(
          text: 'FLAT',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          center + Offset(-textPainter.width / 2, 42 - textPainter.height / 2),
        );
      }
      return;
    }

    // ==========================================================
    // 2. UPRIGHT HORIZON TILT MODE (|z| <= 8.5 m/s²)
    // ==========================================================
    final double rawAngle = math.atan2(x, y);
    // Adjusted cleanly when held in portrait or landscape (cardinal snaps at 0, ±90°, 180°)
    final double cardinal = (rawAngle / (math.pi / 2)).round() * (math.pi / 2);
    final double rollRad = rawAngle - cardinal;
    final bool isLevel = rollRad.abs() <= 0.026; // ±1.5° threshold (0.026 rad)

    // Left and right horizontal reference ticks
    final tickShadow = Paint()
      ..color = Colors.black26
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Left tick: 16px wide
    canvas.drawLine(
      Offset(center.dx - 90, center.dy),
      Offset(center.dx - 74, center.dy),
      tickShadow,
    );
    canvas.drawLine(
      Offset(center.dx - 90, center.dy),
      Offset(center.dx - 74, center.dy),
      tickPaint,
    );

    // Right tick: 16px wide
    canvas.drawLine(
      Offset(center.dx + 74, center.dy),
      Offset(center.dx + 90, center.dy),
      tickShadow,
    );
    canvas.drawLine(
      Offset(center.dx + 74, center.dy),
      Offset(center.dx + 90, center.dy),
      tickPaint,
    );

    // Rotated 140px center horizon bar
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-rollRad);

    const double halfWidth = 70.0;

    final barShadow = Paint()
      ..color = Colors.black26
      ..strokeWidth = isLevel ? 3.4 : 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final barPaint = Paint()
      ..color = isLevel ? Colors.greenAccent : Colors.white.withOpacity(0.75)
      ..strokeWidth = isLevel ? 2.4 : 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw shadow first
    canvas.drawLine(const Offset(-halfWidth, 0), const Offset(halfWidth, 0), barShadow);
    // Draw foreground bar
    canvas.drawLine(const Offset(-halfWidth, 0), const Offset(halfWidth, 0), barPaint);

    // Center alignment pip
    canvas.drawLine(const Offset(0, -4), const Offset(0, 4), barPaint);

    canvas.restore();

    // Subtle degree readout just above the bar
    final double degrees = (rollRad * 180 / math.pi);
    final String degText = isLevel ? '0.0°' : '${degrees.abs().toStringAsFixed(1)}°';
    final textPainter = TextPainter(
      text: TextSpan(
        text: degText,
        style: TextStyle(
          color: isLevel ? Colors.greenAccent : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center + Offset(-textPainter.width / 2, -26),
    );
  }

  @override
  bool shouldRepaint(covariant _HorizonLevelPainter oldDelegate) {
    return oldDelegate.x != x || oldDelegate.y != y || oldDelegate.z != z;
  }
}
