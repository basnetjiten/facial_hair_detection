import 'package:flutter/material.dart';

class FacialHairPainter extends CustomPainter {
  final Map<String, dynamic> facialHairData;
  final Size imageSize;
  final Color hairColor;
  final double strokeWidth;
  final double opacity;

  FacialHairPainter({
    required this.facialHairData,
    required this.imageSize,
    required this.hairColor,
    this.strokeWidth = 2.0,
    this.opacity = 0.7,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final contours = facialHairData['facialHair']['contours'] as List<dynamic>;
    if (contours.isEmpty) return;

    final imageAspect = imageSize.width / imageSize.height;
    final boxAspect = size.width / size.height;

    double drawWidth, drawHeight, dx = 0, dy = 0;
    if (imageAspect > boxAspect) {
      drawHeight = size.height;
      drawWidth = imageSize.width * (size.height / imageSize.height);
      dx = (size.width - drawWidth) / 2;
    } else {
      drawWidth = size.width;
      drawHeight = imageSize.height * (size.width / imageSize.width);
      dy = (size.height - drawHeight) / 2;
    }

    final scaleX = drawWidth / imageSize.width;
    final scaleY = drawHeight / imageSize.height;

    final paint =
        Paint()
          ..color = hairColor.withOpacity(opacity)
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke;

    for (int i = 0; i < contours.length; i++) {
      final point = contours[i];
      final x = (point['x'] as num).toDouble() * scaleX + dx;
      final y = (point['y'] as num).toDouble() * scaleY + dy;

      // Draw small circle for each point
      canvas.drawCircle(Offset(x, y), strokeWidth * 1.5, paint);

      // Connect points with line
      if (i > 0) {
        final prev = contours[i - 1];
        final px = (prev['x'] as num).toDouble() * scaleX + dx;
        final py = (prev['y'] as num).toDouble() * scaleY + dy;
        canvas.drawLine(Offset(px, py), Offset(x, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
