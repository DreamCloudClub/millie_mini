import 'dart:math';

/// A letter problem for the letters quiz
class LetterProblem {
  final String letter; // The letter to display (A or a)
  final String answer; // The letter name to match
  final List<String> aliases; // Alternative acceptable answers

  const LetterProblem({
    required this.letter,
    required this.answer,
    required this.aliases,
  });
}

/// Service for generating letter recognition problems
/// Procedurally generated (no database needed)
class LettersService {
  static const List<String> _uppercaseLetters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
  ];

  static const List<String> _lowercaseLetters = [
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
  ];

  /// Letter name pronunciations and common aliases
  /// Maps uppercase letter to (name, [aliases])
  static const Map<String, (String, List<String>)> _letterInfo = {
    'A': ('A', ['ay', 'eh', 'ah']),
    'B': ('B', ['bee', 'be']),
    'C': ('C', ['see', 'sea', 'cee']),
    'D': ('D', ['dee']),
    'E': ('E', ['ee', 'eee']),
    'F': ('F', ['ef', 'eff']),
    'G': ('G', ['jee', 'gee']),
    'H': ('H', ['aitch', 'ach', 'h']),
    'I': ('I', ['eye', 'ai']),
    'J': ('J', ['jay', 'jai']),
    'K': ('K', ['kay', 'kai']),
    'L': ('L', ['el', 'ell']),
    'M': ('M', ['em', 'emm']),
    'N': ('N', ['en', 'enn']),
    'O': ('O', ['oh', 'o']),
    'P': ('P', ['pee', 'pe']),
    'Q': ('Q', ['cue', 'queue', 'kyu']),
    'R': ('R', ['ar', 'are', 'arr']),
    'S': ('S', ['es', 'ess']),
    'T': ('T', ['tee', 'te']),
    'U': ('U', ['you', 'yu']),
    'V': ('V', ['vee', 've']),
    'W': ('W', ['double you', 'double u', 'doubleyou']),
    'X': ('X', ['ex', 'ecks']),
    'Y': ('Y', ['why', 'wi', 'wai']),
    'Z': ('Z', ['zee', 'zed', 'zee']),
  };

  static final _random = Random();

  /// Generate the next letter problem
  /// [mode]: 'uppercase', 'lowercase', or 'random'
  /// [excludeIds]: Set of letter IDs already shown (e.g., "A", "b")
  /// [sequential]: If true, returns letters in order; if false, random
  static LetterProblem? generate({
    required String mode,
    Set<String>? excludeIds,
  }) {
    final exclude = excludeIds ?? {};

    List<String> availableLetters;
    bool sequential;

    switch (mode) {
      case 'uppercase':
        availableLetters = _uppercaseLetters.where((l) => !exclude.contains(l)).toList();
        sequential = true;
        break;
      case 'lowercase':
        availableLetters = _lowercaseLetters.where((l) => !exclude.contains(l)).toList();
        sequential = true;
        break;
      case 'random':
      default:
        // Mix both cases
        final allLetters = [..._uppercaseLetters, ..._lowercaseLetters];
        availableLetters = allLetters.where((l) => !exclude.contains(l)).toList();
        sequential = false;
        break;
    }

    if (availableLetters.isEmpty) {
      return null; // All letters have been shown
    }

    String letter;
    if (sequential) {
      // Return the first available letter (maintains A-Z order)
      letter = availableLetters.first;
    } else {
      // Random selection
      letter = availableLetters[_random.nextInt(availableLetters.length)];
    }

    // Get the letter info (use uppercase key for lookup)
    final upperLetter = letter.toUpperCase();
    final info = _letterInfo[upperLetter]!;
    final (name, aliases) = info;

    // Include both cases in aliases
    final allAliases = [
      ...aliases,
      letter.toLowerCase(),
      letter.toUpperCase(),
      name.toLowerCase(),
    ];

    return LetterProblem(
      letter: letter,
      answer: name,
      aliases: allAliases,
    );
  }

  /// Get total count of letters for a mode
  static int getLetterCount(String mode) {
    switch (mode) {
      case 'uppercase':
      case 'lowercase':
        return 26;
      case 'random':
      default:
        return 52; // Both cases
    }
  }
}
