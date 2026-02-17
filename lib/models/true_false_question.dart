/// A true/false question for the true/false quiz
class TrueFalseQuestion {
  final String id;
  final String statement;
  final bool answer;
  final String difficulty; // 'easy', 'medium', 'hard'
  final DateTime createdAt;

  const TrueFalseQuestion({
    required this.id,
    required this.statement,
    required this.answer,
    required this.difficulty,
    required this.createdAt,
  });

  factory TrueFalseQuestion.fromJson(Map<String, dynamic> json) {
    return TrueFalseQuestion(
      id: json['id'] as String,
      statement: json['statement'] as String,
      answer: json['answer'] as bool,
      difficulty: json['difficulty'] as String? ?? 'medium',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'statement': statement,
      'answer': answer,
      'difficulty': difficulty,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Get the answer as a string for display/comparison
  String get answerText => answer ? 'True' : 'False';
}
