import 'dart:math';

/// A number problem for the numbers quiz
class NumberProblem {
  final String number; // The number to display (e.g., "7", "42", "123")
  final String answer; // The number as spoken (e.g., "seven", "forty two")
  final List<String> aliases; // Alternative acceptable answers

  const NumberProblem({
    required this.number,
    required this.answer,
    required this.aliases,
  });
}

/// Service for generating number recognition problems
/// Procedurally generated (no database needed)
class NumbersService {
  static final _random = Random();

  /// Number words for 0-19
  static const List<String> _ones = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'
  ];

  /// Tens words
  static const List<String> _tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'
  ];

  /// Convert a number to its word form
  static String _numberToWords(int n) {
    if (n < 0) return 'negative ${_numberToWords(-n)}';
    if (n < 20) return _ones[n];
    if (n < 100) {
      final ten = n ~/ 10;
      final one = n % 10;
      if (one == 0) return _tens[ten];
      return '${_tens[ten]} ${_ones[one]}';
    }
    if (n < 1000) {
      final hundred = n ~/ 100;
      final remainder = n % 100;
      if (remainder == 0) return '${_ones[hundred]} hundred';
      return '${_ones[hundred]} hundred ${_numberToWords(remainder)}';
    }
    return n.toString(); // Fallback for larger numbers
  }

  /// Generate aliases for a number
  static List<String> _generateAliases(int n, String wordForm) {
    final aliases = <String>[
      n.toString(), // The digit form
      wordForm.replaceAll(' ', ''), // No spaces version
    ];

    // Add hyphenated version for compound numbers (twenty-one, etc.)
    if (n >= 21 && n < 100 && n % 10 != 0) {
      final ten = n ~/ 10;
      final one = n % 10;
      aliases.add('${_tens[ten]}-${_ones[one]}');
    }

    // Add "and" version for hundreds (one hundred and twenty)
    if (n >= 100 && n % 100 != 0) {
      final hundred = n ~/ 100;
      final remainder = n % 100;
      aliases.add('${_ones[hundred]} hundred and ${_numberToWords(remainder)}');
    }

    return aliases;
  }

  /// Get the range of numbers for a difficulty level
  static (int, int) _getRangeForDifficulty(String? difficulty) {
    switch (difficulty) {
      case 'easy':
        return (0, 9);
      case 'medium':
        return (10, 99);
      case 'hard':
        return (100, 999);
      default:
        return (0, 9); // Default to easy
    }
  }

  /// Generate the next number problem
  /// [difficulty]: 'easy' (0-9), 'medium' (10-99), 'hard' (100-999)
  /// [excludeIds]: Set of number IDs already shown (e.g., "7", "42")
  static NumberProblem? generate({
    String? difficulty,
    Set<String>? excludeIds,
  }) {
    final exclude = excludeIds ?? {};
    final (minVal, maxVal) = _getRangeForDifficulty(difficulty);

    // Get available numbers
    final availableNumbers = <int>[];
    for (int i = minVal; i <= maxVal; i++) {
      if (!exclude.contains(i.toString())) {
        availableNumbers.add(i);
      }
    }

    if (availableNumbers.isEmpty) {
      return null; // All numbers have been shown
    }

    // Random selection
    final number = availableNumbers[_random.nextInt(availableNumbers.length)];
    final wordForm = _numberToWords(number);
    final aliases = _generateAliases(number, wordForm);

    return NumberProblem(
      number: number.toString(),
      answer: wordForm,
      aliases: aliases,
    );
  }

  /// Get total count of numbers for a difficulty
  static int getNumberCount(String? difficulty) {
    final (minVal, maxVal) = _getRangeForDifficulty(difficulty);
    return maxVal - minVal + 1;
  }
}
