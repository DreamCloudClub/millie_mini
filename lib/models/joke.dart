/// A joke for the jokes quiz
class Joke {
  final String id;
  final String question;
  final String answer;
  final String difficulty; // 'easy', 'medium', 'hard'
  final DateTime createdAt;

  const Joke({
    required this.id,
    required this.question,
    required this.answer,
    required this.difficulty,
    required this.createdAt,
  });

  factory Joke.fromJson(Map<String, dynamic> json) {
    return Joke(
      id: json['id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      difficulty: json['difficulty'] as String? ?? 'medium',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'answer': answer,
      'difficulty': difficulty,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
