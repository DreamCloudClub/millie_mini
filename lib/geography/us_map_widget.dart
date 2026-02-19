import 'package:flutter/material.dart';
import 'us_map_paths.dart';

/// Widget that displays a US map with one state highlighted
/// Shows all states in grey with the selected state in orange
class USMapWidget extends StatelessWidget {
  /// The state ID to highlight (two-letter abbreviation)
  final String? highlightedStateId;

  /// Color for the highlighted state
  final Color highlightColor;

  /// Border color for highlighted state
  final Color highlightBorderColor;

  /// Color for non-highlighted states
  final Color stateColor;

  /// Border color for non-highlighted states
  final Color stateBorderColor;

  /// Background color
  final Color backgroundColor;

  const USMapWidget({
    super.key,
    this.highlightedStateId,
    this.highlightColor = const Color(0xFFFF9800), // Orange
    this.highlightBorderColor = const Color(0xFFE65100), // Dark orange
    this.stateColor = const Color(0xFF424242), // Dark grey
    this.stateBorderColor = const Color(0xFF616161), // Medium grey
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: USMapPaths.viewBoxWidth / USMapPaths.viewBoxHeight,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _USMapPainter(
              highlightedStateId: highlightedStateId?.toUpperCase(),
              highlightColor: highlightColor,
              highlightBorderColor: highlightBorderColor,
              stateColor: stateColor,
              stateBorderColor: stateBorderColor,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _USMapPainter extends CustomPainter {
  final String? highlightedStateId;
  final Color highlightColor;
  final Color highlightBorderColor;
  final Color stateColor;
  final Color stateBorderColor;

  _USMapPainter({
    required this.highlightedStateId,
    required this.highlightColor,
    required this.highlightBorderColor,
    required this.stateColor,
    required this.stateBorderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale to fit the viewBox into the available size
    final scaleX = size.width / USMapPaths.viewBoxWidth;
    final scaleY = size.height / USMapPaths.viewBoxHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Center the map
    final offsetX = (size.width - USMapPaths.viewBoxWidth * scale) / 2;
    final offsetY = (size.height - USMapPaths.viewBoxHeight * scale) / 2;

    // Transform canvas
    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    // Draw all non-highlighted states first
    for (final stateId in USMapPaths.allStateIds) {
      if (stateId == highlightedStateId) continue;

      final pathData = USMapPaths.getPath(stateId);
      if (pathData == null) continue;

      final path = _parseSvgPath(pathData);

      // Fill
      final fillPaint = Paint()
        ..color = stateColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Border
      final borderPaint = Paint()
        ..color = stateBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawPath(path, borderPaint);
    }

    // Draw highlighted state on top with glow effect
    if (highlightedStateId != null) {
      final highlightedPath = USMapPaths.getPath(highlightedStateId!);
      if (highlightedPath != null) {
        final path = _parseSvgPath(highlightedPath);

        // Glow effect
        final glowPaint = Paint()
          ..color = highlightColor.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawPath(path, glowPaint);

        // Fill
        final fillPaint = Paint()
          ..color = highlightColor
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);

        // Border
        final borderPaint = Paint()
          ..color = highlightBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawPath(path, borderPaint);
      }
    }

    canvas.restore();
  }

  /// Parse SVG path data into a Flutter Path
  Path _parseSvgPath(String pathData) {
    final path = Path();
    final commands = _tokenizePath(pathData);

    double currentX = 0;
    double currentY = 0;
    double startX = 0;
    double startY = 0;
    String lastCommand = '';

    int i = 0;
    while (i < commands.length) {
      String cmd = commands[i];

      // If it's a number, repeat the last command
      if (_isNumber(cmd)) {
        cmd = lastCommand;
        i--; // Re-process this token as a parameter
      }

      i++;

      switch (cmd) {
        case 'M': // Move to (absolute)
          currentX = double.parse(commands[i++]);
          currentY = double.parse(commands[i++]);
          path.moveTo(currentX, currentY);
          startX = currentX;
          startY = currentY;
          lastCommand = 'L'; // Subsequent coords are lineTo
          break;

        case 'm': // Move to (relative)
          currentX += double.parse(commands[i++]);
          currentY += double.parse(commands[i++]);
          path.moveTo(currentX, currentY);
          startX = currentX;
          startY = currentY;
          lastCommand = 'l';
          break;

        case 'L': // Line to (absolute)
          currentX = double.parse(commands[i++]);
          currentY = double.parse(commands[i++]);
          path.lineTo(currentX, currentY);
          lastCommand = 'L';
          break;

        case 'l': // Line to (relative)
          currentX += double.parse(commands[i++]);
          currentY += double.parse(commands[i++]);
          path.lineTo(currentX, currentY);
          lastCommand = 'l';
          break;

        case 'H': // Horizontal line (absolute)
          currentX = double.parse(commands[i++]);
          path.lineTo(currentX, currentY);
          lastCommand = 'H';
          break;

        case 'h': // Horizontal line (relative)
          currentX += double.parse(commands[i++]);
          path.lineTo(currentX, currentY);
          lastCommand = 'h';
          break;

        case 'V': // Vertical line (absolute)
          currentY = double.parse(commands[i++]);
          path.lineTo(currentX, currentY);
          lastCommand = 'V';
          break;

        case 'v': // Vertical line (relative)
          currentY += double.parse(commands[i++]);
          path.lineTo(currentX, currentY);
          lastCommand = 'v';
          break;

        case 'Z':
        case 'z': // Close path
          path.close();
          currentX = startX;
          currentY = startY;
          break;

        default:
          // Skip unknown commands
          break;
      }
    }

    return path;
  }

  /// Tokenize SVG path data into commands and numbers
  List<String> _tokenizePath(String pathData) {
    final tokens = <String>[];
    final regex = RegExp(r'([MmLlHhVvZz])|(-?\d+\.?\d*)');

    for (final match in regex.allMatches(pathData)) {
      final token = match.group(0)!;
      if (token.isNotEmpty) {
        tokens.add(token);
      }
    }

    return tokens;
  }

  bool _isNumber(String s) {
    return double.tryParse(s) != null;
  }

  @override
  bool shouldRepaint(covariant _USMapPainter oldDelegate) {
    return oldDelegate.highlightedStateId != highlightedStateId ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.stateColor != stateColor;
  }
}
