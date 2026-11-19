import 'package:flutter/material.dart';

/// Lightweight Guidance Grid overlay widget for the live camera viewfinder.
///
/// Supports 'off', '3x3' (Rule of Thirds), and '4x4' grid modes.
/// Wrapped in IgnorePointer so pinch-to-zoom and tap-to-focus pass straight through.
class CameraGridOverlay extends StatelessWidget {
  final String gridMode;

  const CameraGridOverlay({
    super.key,
    required this.gridMode,
  });

  @override
  Widget build(BuildContext context) {
    if (gridMode.toLowerCase() == 'off') {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: CustomPaint(
        painter: _CameraGridPainter(gridMode: gridMode),
        size: Size.infinite,
      ),
    );
  }
}

class _CameraGridPainter extends CustomPainter {
  final String gridMode;

  _CameraGridPainter({required this.gridMode});

  @override
  void paint(Canvas canvas, Size size) {
    final int divisions;
    if (gridMode == '4x4') {
      divisions = 4;
    } else {
      // Default to 3x3 (Rule of Thirds)
      divisions = 3;
    }

    // Underlying shadow paint for contrast against light/sky backgrounds
    final shadowPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    // Subtle crisp foreground white paint
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final double stepX = size.width / divisions;
    final double stepY = size.height / divisions;

    // 1. Draw shadow lines first
    for (int i = 1; i < divisions; i++) {
      final double x = stepX * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), shadowPaint);
    }
    for (int i = 1; i < divisions; i++) {
      final double y = stepY * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), shadowPaint);
    }

    // 2. Draw foreground white lines over shadows
    for (int i = 1; i < divisions; i++) {
      final double x = stepX * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (int i = 1; i < divisions; i++) {
      final double y = stepY * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CameraGridPainter oldDelegate) {
    return oldDelegate.gridMode != gridMode;
  }
}
