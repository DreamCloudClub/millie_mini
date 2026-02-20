import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget that displays a complete US map with dynamic state highlighting.
///
/// Uses a single SVG file containing all 50 states. Each state is a path
/// element with id=USPS code (e.g., id="TX", id="CA").
///
/// Default styling: Light blue fill with darker blue borders.
/// Featured state styling: Orange fill with lighter orange borders.
class USStatesMapWidget extends StatefulWidget {
  /// The state code to highlight (two-letter USPS code, e.g., "TX", "CA").
  /// If null, all states use default styling.
  final String? featuredStateCode;

  /// Callback when the SVG is loaded and ready.
  final VoidCallback? onLoaded;

  const USStatesMapWidget({
    super.key,
    this.featuredStateCode,
    this.onLoaded,
  });

  @override
  State<USStatesMapWidget> createState() => _USStatesMapWidgetState();
}

class _USStatesMapWidgetState extends State<USStatesMapWidget> {
  String? _svgString;
  bool _isLoading = true;

  // Default styling - Light blue fill, darker blue border
  static const String _defaultFill = '#CFE8FF';
  static const String _defaultStroke = '#5BA3D9';

  // Featured state styling - Orange
  static const String _featuredFill = '#FFA726';
  static const String _featuredStroke = '#FFCC80';

  // Stroke width
  static const String _strokeWidth = '0.5';

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  @override
  void didUpdateWidget(USStatesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featuredStateCode != widget.featuredStateCode) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    setState(() => _isLoading = true);

    try {
      // Load the base SVG
      final rawSvg = await rootBundle.loadString('assets/svg/us_states_map.svg');

      // Apply dynamic styling by modifying path attributes
      final styledSvg = _applyInlineStyles(rawSvg);

      setState(() {
        _svgString = styledSvg;
        _isLoading = false;
      });

      widget.onLoaded?.call();
    } catch (e) {
      debugPrint('USStatesMapWidget: Error loading SVG: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Apply inline styles to each path element in the SVG.
  String _applyInlineStyles(String svgContent) {
    final featuredCode = widget.featuredStateCode?.toLowerCase();

    // Remove the CSS <style> block - flutter_svg doesn't support CSS and it can
    // interfere with inline styles. The style block is inside <defs>...</defs>
    var styledSvg = svgContent.replaceAll(
      RegExp(r'<style[^>]*>.*?</style>', multiLine: true, dotAll: true),
      '',
    );

    // Regular expression to find path elements with class attribute (e.g., class="al")
    final pathRegex = RegExp(r'<path\s+class="([a-z]{2})"', multiLine: true);

    return styledSvg.replaceAllMapped(pathRegex, (match) {
      final stateId = match.group(1)!;
      final isFeatured = stateId == featuredCode;

      final fill = isFeatured ? _featuredFill : _defaultFill;
      final stroke = isFeatured ? _featuredStroke : _defaultStroke;

      return '<path class="$stateId" fill="$fill" stroke="$stroke" stroke-width="$_strokeWidth"';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _svgString == null) {
      return const AspectRatio(
        aspectRatio: 959 / 593, // US map standard proportions
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 959 / 593, // US map standard proportions (landscape)
      child: SvgPicture.string(
        _svgString!,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Full-page widget for displaying the US states map in lessons.
///
/// Provides a landscape-oriented map that fills most of the screen width,
/// with optional state information display.
class USStatesMapPage extends StatelessWidget {
  /// The state code to highlight (two-letter USPS code).
  final String? featuredStateCode;

  /// Optional state name to display.
  final String? stateName;

  /// Optional callback when a state is tapped.
  final ValueChanged<String>? onStateTapped;

  /// Background color for the page.
  final Color backgroundColor;

  const USStatesMapPage({
    super.key,
    this.featuredStateCode,
    this.stateName,
    this.onStateTapped,
    this.backgroundColor = const Color(0xFFF5F5F5),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // State name header (if provided)
            if (stateName != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  stateName!,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
            // Map takes most of the space
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: USStatesMapWidget(
                    featuredStateCode: featuredStateCode,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
