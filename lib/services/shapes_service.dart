import 'dart:math';

/// A shape problem for the shapes game
class ShapeProblem {
  final String id;
  final String answer;
  final List<String> aliases;
  final String hint; // "This shape has 3 sides. What is it?"
  final String assetPath; // Path to PNG image

  const ShapeProblem({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.hint,
    required this.assetPath,
  });
}

/// Service for procedurally generating shape problems
class ShapesService {
  static final _random = Random();

  /// All available shapes with their images and descriptions
  static const List<_ShapeData> _shapes = [
    _ShapeData(
      id: 'triangle',
      answer: 'Triangle',
      aliases: ['a triangle', 'the triangle'],
      hint: 'This shape has 3 sides. What is it?',
      assetPath: 'assets/shapes/triangle.png',
    ),
    _ShapeData(
      id: 'square',
      answer: 'Square',
      aliases: ['a square', 'the square'],
      hint: 'This shape has 4 equal sides. What is it?',
      assetPath: 'assets/shapes/square.png',
    ),
    _ShapeData(
      id: 'rectangle',
      answer: 'Rectangle',
      aliases: ['a rectangle', 'the rectangle'],
      hint: 'This shape has 2 long sides and 2 short sides. What is it?',
      assetPath: 'assets/shapes/rectangle.png',
    ),
    _ShapeData(
      id: 'circle',
      answer: 'Circle',
      aliases: ['a circle', 'the circle'],
      hint: 'This shape is round with no corners. What is it?',
      assetPath: 'assets/shapes/circle.png',
    ),
    _ShapeData(
      id: 'star',
      answer: 'Star',
      aliases: ['a star', 'the star'],
      hint: 'This shape has 5 points. What is it?',
      assetPath: 'assets/shapes/star.png',
    ),
    _ShapeData(
      id: 'heart',
      answer: 'Heart',
      aliases: ['a heart', 'the heart'],
      hint: 'This shape means love. What is it?',
      assetPath: 'assets/shapes/heart.png',
    ),
    _ShapeData(
      id: 'crescent',
      answer: 'Crescent',
      aliases: ['a crescent', 'the crescent', 'moon', 'a moon', 'the moon', 'crescent moon'],
      hint: 'This shape looks like the moon at night. What is it?',
      assetPath: 'assets/shapes/crescent.png',
    ),
    _ShapeData(
      id: 'pentagon',
      answer: 'Pentagon',
      aliases: ['a pentagon', 'the pentagon'],
      hint: 'This shape has 5 sides. What is it?',
      assetPath: 'assets/shapes/pentagon.png',
    ),
    _ShapeData(
      id: 'hexagon',
      answer: 'Hexagon',
      aliases: ['a hexagon', 'the hexagon'],
      hint: 'This shape has 6 sides. What is it?',
      assetPath: 'assets/shapes/hexagon.png',
    ),
    _ShapeData(
      id: 'oval',
      answer: 'Oval',
      aliases: ['an oval', 'the oval', 'ellipse', 'an ellipse', 'egg', 'an egg'],
      hint: 'This shape is like a stretched circle. What is it?',
      assetPath: 'assets/shapes/oval.png',
    ),
  ];

  /// Generate a random shape problem
  /// Returns null if all shapes have been shown (based on excludeIds)
  static ShapeProblem? generate({Set<String>? excludeIds}) {
    // Filter out already-shown shapes
    final available = _shapes
        .where((s) => excludeIds == null || !excludeIds.contains(s.id))
        .toList();

    if (available.isEmpty) {
      return null; // All shapes shown
    }

    // Pick a random shape
    final shape = available[_random.nextInt(available.length)];

    return ShapeProblem(
      id: shape.id,
      answer: shape.answer,
      aliases: shape.aliases,
      hint: shape.hint,
      assetPath: shape.assetPath,
    );
  }

  /// Get asset path for a shape by ID
  static String? getAssetPath(String shapeId) {
    for (final shape in _shapes) {
      if (shape.id == shapeId) {
        return shape.assetPath;
      }
    }
    return null;
  }

  /// Get total number of shapes available
  static int get totalShapes => _shapes.length;
}

/// Internal shape data class
class _ShapeData {
  final String id;
  final String answer;
  final List<String> aliases;
  final String hint;
  final String assetPath;

  const _ShapeData({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.hint,
    required this.assetPath,
  });
}
