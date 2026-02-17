import 'dart:math';

/// A generated math problem
class MathProblem {
  final String question; // "24 + 16"
  final String answer;   // "40"
  final String operation; // "addition", "subtraction", "multiplication", "division"

  const MathProblem({
    required this.question,
    required this.answer,
    required this.operation,
  });
}

/// Service for procedurally generating math problems
class MathProblemService {
  static final _random = Random();

  /// Generate a random math problem based on difficulty and operation
  ///
  /// Difficulty strategy based on cognitive load, not just digit count:
  /// - Easy: 1-digit op 1-digit (single digit operands)
  /// - Medium: 2-digit op 1-digit (one multi-digit operand)
  /// - Hard: 2-digit op 2-digit (two multi-digit operands)
  ///
  /// Operations: 'addition', 'subtraction', 'multiplication', 'division', 'random' (or null)
  static MathProblem generate({String? difficulty, String? operation}) {
    // Normalize difficulty - default to 'easy' if null or empty
    final diff = (difficulty?.toLowerCase().isNotEmpty == true)
        ? difficulty!.toLowerCase()
        : 'easy';
    final op = operation?.toLowerCase();

    // If specific operation requested, use it; otherwise pick random
    if (op == 'addition') {
      return _generateAddition(diff);
    } else if (op == 'subtraction') {
      return _generateSubtraction(diff);
    } else if (op == 'multiplication') {
      return _generateMultiplication(diff);
    } else if (op == 'division') {
      return _generateDivision(diff);
    }

    // Random operation: 0=add, 1=subtract, 2=multiply, 3=divide
    final opIndex = _random.nextInt(4);

    return switch (opIndex) {
      0 => _generateAddition(diff),
      1 => _generateSubtraction(diff),
      2 => _generateMultiplication(diff),
      3 => _generateDivision(diff),
      _ => _generateAddition(diff),
    };
  }

  /// Generate an addition problem
  /// Easy: 1-9 + 1-9 (max result ~18)
  /// Medium: 10-99 + 1-9 (max result ~108)
  /// Hard: 10-99 + 10-99 (max result ~198)
  static MathProblem _generateAddition(String diff) {
    int a, b;

    switch (diff) {
      case 'hard':
        // 2-digit + 2-digit
        a = _randomInRange(10, 99);
        b = _randomInRange(10, 99);
        break;
      case 'medium':
        // 2-digit + 1-digit
        a = _randomInRange(10, 99);
        b = _randomInRange(1, 9);
        break;
      default:
        // Easy: 1-digit + 1-digit
        a = _randomInRange(1, 9);
        b = _randomInRange(1, 9);
    }

    final result = a + b;

    return MathProblem(
      question: '$a + $b',
      answer: '$result',
      operation: 'addition',
    );
  }

  /// Generate a subtraction problem
  /// Ensures positive result by making first number >= second
  /// Easy: 1-9 - 1-9 (single digits)
  /// Medium: 10-99 - 1-9 (2-digit minus 1-digit)
  /// Hard: 10-99 - 10-99 (2-digit minus 2-digit)
  static MathProblem _generateSubtraction(String diff) {
    int a, b;

    switch (diff) {
      case 'hard':
        // 2-digit - 2-digit
        a = _randomInRange(10, 99);
        b = _randomInRange(10, 99);
        break;
      case 'medium':
        // 2-digit - 1-digit
        a = _randomInRange(10, 99);
        b = _randomInRange(1, 9);
        break;
      default:
        // Easy: 1-digit - 1-digit
        a = _randomInRange(1, 9);
        b = _randomInRange(1, 9);
    }

    // Ensure a >= b for positive result
    if (b > a) {
      final temp = a;
      a = b;
      b = temp;
    }

    final result = a - b;

    return MathProblem(
      question: '$a - $b',
      answer: '$result',
      operation: 'subtraction',
    );
  }

  /// Generate a multiplication problem
  /// Easy: small numbers (1-5 × 1-5, max result 25)
  /// Medium: 1-9 × 1-9 (max result 81)
  /// Hard: 10-50 × 2-9 (max result ~450)
  static MathProblem _generateMultiplication(String diff) {
    int a, b;

    switch (diff) {
      case 'hard':
        // 2-digit × 1-digit (larger ranges)
        a = _randomInRange(10, 50);
        b = _randomInRange(2, 9);
        break;
      case 'medium':
        // Full times tables (1-9 × 1-9)
        a = _randomInRange(1, 9);
        b = _randomInRange(1, 9);
        break;
      default:
        // Easy: small multiplication (max 5×5=25)
        a = _randomInRange(1, 5);
        b = _randomInRange(1, 5);
    }

    final result = a * b;

    return MathProblem(
      question: '$a × $b',
      answer: '$result',
      operation: 'multiplication',
    );
  }

  /// Generate a division problem
  /// Generates answer first, then picks divisor, computes dividend
  /// This ensures clean integer results (no decimals)
  /// Easy: single digit ÷ single digit (e.g., 6 ÷ 2 = 3, 9 ÷ 3 = 3)
  /// Medium: 2-digit dividend ÷ 1-digit divisor (e.g., 24 ÷ 6 = 4)
  /// Hard: 2-digit ÷ 2-digit (e.g., 144 ÷ 12 = 12)
  static MathProblem _generateDivision(String diff) {
    int answer, divisor, dividend;

    switch (diff) {
      case 'hard':
        // 2-digit ÷ 2-digit
        divisor = _randomInRange(10, 15);
        answer = _randomInRange(2, 9);
        break;
      case 'medium':
        // 2-digit ÷ 1-digit (dividend 10-99)
        divisor = _randomInRange(2, 9);
        final minAnswer = (10 / divisor).ceil();
        final maxAnswer = 99 ~/ divisor;
        answer = _randomInRange(minAnswer, maxAnswer);
        break;
      default:
        // Easy: single digit ÷ single digit (dividend stays 1-9)
        // divisor 2-3, answer 1-3 keeps dividend ≤ 9
        divisor = _randomInRange(2, 3);
        answer = _randomInRange(1, 3);
    }

    dividend = answer * divisor;

    return MathProblem(
      question: '$dividend ÷ $divisor',
      answer: '$answer',
      operation: 'division',
    );
  }

  /// Generate a random integer in range [min, max] inclusive
  static int _randomInRange(int min, int max) {
    return min + _random.nextInt(max - min + 1);
  }
}
