/// A riddle for the riddles quiz
class Riddle {
  final String id;
  final String question;
  final String answer;
  final String difficulty; // 'easy', 'medium', 'hard'
  final DateTime createdAt;

  const Riddle({
    required this.id,
    required this.question,
    required this.answer,
    required this.difficulty,
    required this.createdAt,
  });

  factory Riddle.fromJson(Map<String, dynamic> json) {
    return Riddle(
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
