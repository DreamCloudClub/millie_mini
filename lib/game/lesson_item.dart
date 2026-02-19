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

  /// No grading - auto-advance after TTS
  /// Good for: Lessons, demonstrations
  none,
}

/// A lesson item (riddle, joke, trivia question, spelling, etc.)
class LessonItem {
  final String id;
  final String type; // 'riddle', 'joke', 'trivia', 'spelling'
  final String prompt; // The question/riddle text (or word for spelling)
  final String answer; // The correct answer
  final List<String> aliases; // Alternative correct answers
  final GradingType gradingType; // How to evaluate the answer
  final double? numericTolerance; // For numeric grading type
  final String? lettersPhonetic; // Phonetic pronunciation of letters for TTS
  final String? cachedAudioUrl; // Cached TTS audio URL (for animals, etc.)
  final String? imageUrl; // Image URL (for animals, shapes, etc.)
  final String? stateId; // Two-letter state abbreviation (for geography)
  final String? stateCapital; // State capital (for geography)
  final String? stateRegion; // State region (for geography)

  const LessonItem({
    required this.id,
    required this.type,
    required this.prompt,
    required this.answer,
    this.aliases = const [],
    this.gradingType = GradingType.flexible,
    this.numericTolerance,
    this.lettersPhonetic,
    this.cachedAudioUrl,
    this.imageUrl,
    this.stateId,
    this.stateCapital,
    this.stateRegion,
  });

  /// Get the text to speak via TTS (different from display for spelling/math)
  String get ttsPrompt {
    if (gradingType == GradingType.spelling) {
      return 'How do you spell $prompt?';
    }
    if (type == 'letters') {
      // Don't say the letter - just ask the question
      return 'What is this letter?';
    }
    if (type == 'numbers') {
      // Don't say the number - just ask the question
      return 'What is this number?';
    }
    if (type == 'math') {
      // Convert math symbols to spoken words for TTS
      return prompt
          .replaceAll('+', 'plus')
          .replaceAll('-', 'minus')
          .replaceAll('×', 'times')
          .replaceAll('÷', 'divided by');
    }
    return prompt;
  }

  /// Get the text to display on screen (just the word for spelling)
  String get displayText {
    // For spelling, just show the word (displayed large)
    // For others, show the full question
    return prompt;
  }

  /// Check if this is a multi-digit math problem (for stacked display)
  /// Returns true if either operand has 2+ digits
  bool get isMultiDigitMath {
    if (type != 'math') return false;

    // Match patterns like "88 × 12", "5 + 3", "45 - 8", "24 ÷ 6"
    final regex = RegExp(r'^(\d+)\s*[+\-×÷]\s*(\d+)$');
    final match = regex.firstMatch(prompt.trim());

    if (match == null) return false;

    final num1 = match.group(1)!;
    final num2 = match.group(2)!;

    return num1.length >= 2 || num2.length >= 2;
  }

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
      case GradingType.none:
        // Lessons don't grade - always return true
        return true;
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

  /// Spelling match - handles letter-by-letter input
  /// Normalizes: extracts only letters, compares lowercase
  /// Handles "a p p l e", "A P P L E", "apple", etc.
  bool _checkSpelling(String userAnswer) {
    // Normalize: extract only letters, lowercase
    final userLetters = userAnswer
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]'), ''); // Remove spaces, punctuation

    final answerLetters = answer.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

    if (userLetters == answerLetters) {
      return true;
    }

    // Check aliases too
    for (final alias in aliases) {
      final aliasLetters = alias.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (userLetters == aliasLetters) {
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
  /// Handles both digit strings ("40") and spoken words ("forty")
  bool _checkNumeric(String userAnswer) {
    final userNum = _parseSpokenNumber(userAnswer);
    final expectedNum = double.tryParse(answer.trim());

    if (userNum == null || expectedNum == null) {
      // Fall back to exact match if parsing fails
      return _checkExact(userAnswer);
    }

    final tolerance = numericTolerance ?? 0.0;
    return (userNum - expectedNum).abs() <= tolerance;
  }

  /// Parse a number from either digits or spoken words
  /// Handles: "40", "forty", "forty-two", "one hundred twenty three", etc.
  static double? _parseSpokenNumber(String input) {
    final cleaned = input.toLowerCase().trim();

    // Try direct parse first (handles "40", "123", etc.)
    final direct = double.tryParse(cleaned.replaceAll(RegExp(r'[^\d.-]'), ''));
    if (direct != null) return direct;

    // Convert spoken words to number
    return _wordsToNumber(cleaned);
  }

  static final Map<String, int> _wordToNum = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
    'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
    'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
    'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30,
    'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70,
    'eighty': 80, 'ninety': 90,
  };

  static final Map<String, int> _multipliers = {
    'hundred': 100,
    'thousand': 1000,
  };

  /// Convert spoken number words to a numeric value
  static double? _wordsToNumber(String input) {
    // Normalize: replace hyphens with spaces, remove extra spaces
    final normalized = input
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'[^a-z\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) return null;

    final words = normalized.split(' ');
    int total = 0;
    int current = 0;

    for (final word in words) {
      if (_wordToNum.containsKey(word)) {
        current += _wordToNum[word]!;
      } else if (_multipliers.containsKey(word)) {
        if (current == 0) current = 1;
        current *= _multipliers[word]!;
        if (word == 'thousand') {
          total += current;
          current = 0;
        }
      } else if (word == 'and') {
        // Skip "and" (e.g., "one hundred and twenty")
        continue;
      } else {
        // Unknown word - can't parse
        return null;
      }
    }

    total += current;
    return total > 0 || normalized == 'zero' ? total.toDouble() : null;
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
    final category = map['type'] as String? ?? map['category'] as String? ?? '';

    // Parse grading type from string, or infer from category
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
    } else if (category == 'spelling') {
      // Auto-set spelling grading type for spelling category
      gradingType = GradingType.spelling;
    }

    return LessonItem(
      id: map['id'] as String,
      type: category.isEmpty ? 'riddle' : category,
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
      if (lettersPhonetic != null) 'letters_phonetic': lettersPhonetic,
    };
  }

  @override
  String toString() {
    return 'LessonItem(id: $id, type: $type, grading: ${gradingType.name}, '
        'prompt: ${prompt.substring(0, prompt.length > 30 ? 30 : prompt.length)}...)';
  }
}
