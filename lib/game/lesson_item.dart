/// Grading type for answer evaluation
/// Determines how strictly the user's answer is compared to the expected answer
enum GradingType {
  /// Default: Flexible matching with normalization, aliases, and word overlap
  /// Good for: Riddles, trivia, general knowledge
  flexible,

  /// Exact match required (case-insensitive, trimmed)
  /// Good for: Spelling tests, specific vocabulary
  exact,

  /// Exact spelling required (case-sensitive)
  /// Good for: Spelling bees, proper nouns
  spelling,

  /// Contains the answer somewhere in the response
  /// Good for: Open-ended questions, definitions
  contains,

  /// Numeric comparison with tolerance
  /// Good for: Math problems, measurements
  numeric,
}

/// A lesson item (riddle, joke, trivia question, etc.)
class LessonItem {
  final String id;
  final String type; // 'riddle', 'joke', 'trivia'
  final String prompt; // The question/riddle text
  final String answer; // The correct answer
  final List<String> aliases; // Alternative correct answers
  final GradingType gradingType; // How to evaluate the answer
  final double? numericTolerance; // For numeric grading type

  const LessonItem({
    required this.id,
    required this.type,
    required this.prompt,
    required this.answer,
    this.aliases = const [],
    this.gradingType = GradingType.flexible,
    this.numericTolerance,
  });

  /// Deterministic answer checking - uses gradingType to determine strategy
  bool checkAnswer(String userAnswer) {
    switch (gradingType) {
      case GradingType.exact:
        return _checkExact(userAnswer);
      case GradingType.spelling:
        return _checkSpelling(userAnswer);
      case GradingType.contains:
        return _checkContains(userAnswer);
      case GradingType.numeric:
        return _checkNumeric(userAnswer);
      case GradingType.flexible:
        return _checkFlexible(userAnswer);
    }
  }

  /// Exact match (case-insensitive, trimmed)
  bool _checkExact(String userAnswer) {
    final normalized = userAnswer.toLowerCase().trim();
    if (normalized == answer.toLowerCase().trim()) {
      return true;
    }
    for (final alias in aliases) {
      if (normalized == alias.toLowerCase().trim()) {
        return true;
      }
    }
    return false;
  }

  /// Spelling match (case-sensitive)
  bool _checkSpelling(String userAnswer) {
    final trimmed = userAnswer.trim();
    if (trimmed == answer.trim()) {
      return true;
    }
    for (final alias in aliases) {
      if (trimmed == alias.trim()) {
        return true;
      }
    }
    return false;
  }

  /// Contains check
  bool _checkContains(String userAnswer) {
    final normalizedUser = userAnswer.toLowerCase().trim();
    final normalizedAnswer = answer.toLowerCase().trim();

    if (normalizedUser.contains(normalizedAnswer) ||
        normalizedAnswer.contains(normalizedUser)) {
      return true;
    }

    for (final alias in aliases) {
      final normalizedAlias = alias.toLowerCase().trim();
      if (normalizedUser.contains(normalizedAlias) ||
          normalizedAlias.contains(normalizedUser)) {
        return true;
      }
    }
    return false;
  }

  /// Numeric comparison with tolerance
  bool _checkNumeric(String userAnswer) {
    final userNum = double.tryParse(userAnswer.trim().replaceAll(RegExp(r'[^\d.-]'), ''));
    final expectedNum = double.tryParse(answer.trim().replaceAll(RegExp(r'[^\d.-]'), ''));

    if (userNum == null || expectedNum == null) {
      // Fall back to exact match if parsing fails
      return _checkExact(userAnswer);
    }

    final tolerance = numericTolerance ?? 0.0;
    return (userNum - expectedNum).abs() <= tolerance;
  }

  /// Flexible matching (original behavior)
  bool _checkFlexible(String userAnswer) {
    final normalizedUser = _normalize(userAnswer);

    // Check against primary answer
    if (_matchesAnswer(normalizedUser, _normalize(answer))) {
      return true;
    }

    // Check against aliases
    for (final alias in aliases) {
      if (_matchesAnswer(normalizedUser, _normalize(alias))) {
        return true;
      }
    }

    return false;
  }

  /// Normalize a string for comparison
  static String _normalize(String text) {
    return text
        .toLowerCase()
        .trim()
        // Remove common filler words
        .replaceAll(RegExp(r'\b(a|an|the|is|it|its)\b'), ' ')
        // Remove punctuation
        .replaceAll(RegExp(r'[^\w\s]'), '')
        // Collapse whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Check if user answer matches expected answer
  static bool _matchesAnswer(String userNormalized, String expectedNormalized) {
    // Exact match
    if (userNormalized == expectedNormalized) {
      return true;
    }

    // User answer contains the expected answer
    if (userNormalized.contains(expectedNormalized)) {
      return true;
    }

    // Expected answer contains the user answer (if user answer is substantial)
    if (userNormalized.length >= 3 &&
        expectedNormalized.contains(userNormalized)) {
      return true;
    }

    // Word overlap check - if most significant words match
    final userWords = _getSignificantWords(userNormalized);
    final expectedWords = _getSignificantWords(expectedNormalized);

    if (userWords.isEmpty || expectedWords.isEmpty) {
      return false;
    }

    // Check if any significant words from expected are in user answer
    final matchingWords = userWords.intersection(expectedWords);
    if (matchingWords.isNotEmpty) {
      // At least one significant word matches
      // For short answers (1-2 words), require exact match
      if (expectedWords.length <= 2) {
        return matchingWords.length == expectedWords.length;
      }
      // For longer answers, allow partial match
      return matchingWords.length >= (expectedWords.length * 0.5).ceil();
    }

    return false;
  }

  /// Extract significant words (length > 2) from text
  static Set<String> _getSignificantWords(String text) {
    return text
        .split(' ')
        .where((w) => w.length > 2)
        .toSet();
  }

  /// Create from database map
  factory LessonItem.fromMap(Map<String, dynamic> map) {
    // Parse grading type from string
    GradingType gradingType = GradingType.flexible;
    final gradingStr = map['grading_type'] as String?;
    if (gradingStr != null) {
      switch (gradingStr.toLowerCase()) {
        case 'exact':
          gradingType = GradingType.exact;
          break;
        case 'spelling':
          gradingType = GradingType.spelling;
          break;
        case 'contains':
          gradingType = GradingType.contains;
          break;
        case 'numeric':
          gradingType = GradingType.numeric;
          break;
      }
    }

    return LessonItem(
      id: map['id'] as String,
      type: map['type'] as String? ?? map['category'] as String? ?? 'riddle',
      prompt: map['prompt'] as String? ?? map['question'] as String? ?? '',
      answer: map['answer'] as String? ?? '',
      aliases: (map['aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      gradingType: gradingType,
      numericTolerance: (map['numeric_tolerance'] as num?)?.toDouble(),
    );
  }

  /// Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'prompt': prompt,
      'answer': answer,
      'aliases': aliases,
      'grading_type': gradingType.name,
      if (numericTolerance != null) 'numeric_tolerance': numericTolerance,
    };
  }

  @override
  String toString() {
    return 'LessonItem(id: $id, type: $type, grading: ${gradingType.name}, '
        'prompt: ${prompt.substring(0, prompt.length > 30 ? 30 : prompt.length)}...)';
  }
}
