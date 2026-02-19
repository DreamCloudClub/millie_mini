import 'package:flutter/material.dart';

/// Widget that displays a state silhouette with customizable colors
/// Uses simplified polygon rendering for the seed states
/// Can be upgraded to SVG rendering for better accuracy
class StateSilhouetteWidget extends StatelessWidget {
  /// The state ID (two-letter abbreviation)
  final String stateId;

  /// Fill color for the silhouette
  final Color fillColor;

  /// Border color for the silhouette
  final Color borderColor;

  /// Border width
  final double borderWidth;

  const StateSilhouetteWidget({
    super.key,
    required this.stateId,
    this.fillColor = const Color(0xFF2196F3),
    this.borderColor = const Color(0xFF1565C0),
    this.borderWidth = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _getAspectRatio(stateId),
      child: CustomPaint(
        painter: StateSilhouettePainter(
          stateId: stateId,
          fillColor: fillColor,
          borderColor: borderColor,
          borderWidth: borderWidth,
        ),
        size: Size.infinite,
      ),
    );
  }

  /// Get approximate aspect ratio for a state
  double _getAspectRatio(String stateId) {
    switch (stateId.toUpperCase()) {
      case 'CA':
        return 0.6; // Taller than wide
      case 'TX':
        return 1.1; // Roughly square
      case 'NY':
        return 1.3; // Wider
      case 'FL':
        return 0.7; // Taller due to peninsula
      case 'AZ':
        return 0.85; // Roughly square
      case 'WA':
        return 1.4; // Wider
      case 'CO':
        return 1.3; // Rectangle, wider
      case 'IL':
        return 0.5; // Much taller
      case 'GA':
        return 0.8; // Slightly taller
      case 'OH':
        return 0.9; // Roughly square
      default:
        return 1.0;
    }
  }
}

/// Custom painter for state silhouettes
class StateSilhouettePainter extends CustomPainter {
  final String stateId;
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;

  StateSilhouettePainter({
    required this.stateId,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final points = _getStatePoints(stateId.toUpperCase());
    if (points.isEmpty) {
      // Fallback: draw a rounded rectangle
      _drawFallbackShape(canvas, size);
      return;
    }

    // Calculate bounds to scale properly
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final point in points) {
      if (point[0] < minX) minX = point[0];
      if (point[0] > maxX) maxX = point[0];
      if (point[1] < minY) minY = point[1];
      if (point[1] > maxY) maxY = point[1];
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final padding = 10.0;

    // Scale to fit with padding
    final scaleX = (size.width - padding * 2) / width;
    final scaleY = (size.height - padding * 2) / height;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Center the shape
    final offsetX = (size.width - width * scale) / 2 - minX * scale;
    final offsetY = (size.height - height * scale) / 2 - minY * scale;

    // Build the path
    final path = Path();
    bool first = true;
    for (final point in points) {
      final x = point[0] * scale + offsetX;
      final y = point[1] * scale + offsetY;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Draw fill
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, borderPaint);
  }

  void _drawFallbackShape(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, 10, size.width - 20, size.height - 20),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant StateSilhouettePainter oldDelegate) {
    return oldDelegate.stateId != stateId ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor;
  }

  /// Detailed polygon points for each seed state
  /// Coordinates are in an arbitrary space, will be scaled to fit
  List<List<double>> _getStatePoints(String stateId) {
    switch (stateId) {
      case 'CA':
        return [
          [20, 5], [35, 0], [50, 5], [55, 15], [60, 30],
          [65, 50], [70, 70], [65, 90], [55, 100], [45, 105],
          [35, 100], [25, 90], [15, 75], [10, 55], [5, 35],
          [10, 20],
        ];
      case 'TX':
        return [
          [10, 20], [30, 10], [50, 5], [70, 5], [90, 10],
          [95, 25], [100, 45], [95, 65], [85, 80], [70, 90],
          [50, 95], [30, 90], [15, 75], [5, 55], [5, 35],
        ];
      case 'NY':
        return [
          [5, 40], [15, 20], [35, 10], [60, 5], [80, 10],
          [95, 25], [100, 40], [95, 60], [80, 75], [60, 80],
          [40, 75], [20, 65], [10, 50],
        ];
      case 'FL':
        return [
          [10, 10], [40, 5], [80, 10], [90, 20], [85, 35],
          [75, 50], [65, 70], [50, 90], [35, 100], [25, 90],
          [20, 70], [15, 50], [10, 30],
        ];
      case 'AZ':
        return [
          [5, 5], [95, 5], [95, 75], [80, 95], [50, 95],
          [20, 95], [5, 75],
        ];
      case 'WA':
        return [
          [5, 35], [15, 15], [35, 5], [60, 5], [85, 10],
          [95, 25], [90, 45], [75, 60], [55, 70], [35, 70],
          [15, 60], [5, 45],
        ];
      case 'CO':
        // Colorado is a rectangle
        return [
          [5, 5], [95, 5], [95, 95], [5, 95],
        ];
      case 'IL':
        return [
          [30, 5], [70, 5], [80, 20], [85, 45], [80, 70],
          [70, 90], [50, 95], [30, 90], [20, 70], [15, 45],
          [20, 20],
        ];
      case 'GA':
        return [
          [10, 15], [40, 5], [70, 5], [90, 15], [95, 35],
          [90, 60], [80, 80], [60, 90], [35, 95], [15, 80],
          [5, 55], [5, 30],
        ];
      case 'OH':
        return [
          [15, 15], [45, 5], [75, 10], [90, 25], [95, 50],
          [85, 75], [65, 90], [40, 95], [20, 85], [5, 60],
          [5, 35],
        ];
      default:
        return [];
    }
  }
}
