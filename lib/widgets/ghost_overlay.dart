import 'dart:io';
import 'package:flutter/material.dart';

/// Semi-transparent reference photo overlay displayed above the camera preview.
/// Enables "Before & After" site inspection alignment and visual comparison.
class GhostOverlay extends StatelessWidget {
  final File file;
  final double opacity;

  const GhostOverlay({
    super.key,
    required this.file,
    this.opacity = 0.35,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}
