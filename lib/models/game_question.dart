/// A game question (riddle, joke, or trivia)
class GameQuestion {
  final String id;
  final String category; // 'riddle', 'joke', 'trivia'
  final String question;
  final String answer;
  final String difficulty; // 'easy', 'medium', 'hard'
  final DateTime? lastUsedAt;
  final DateTime createdAt;

  const GameQuestion({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.difficulty = 'medium',
    this.lastUsedAt,
    required this.createdAt,
  });

  factory GameQuestion.fromJson(Map<String, dynamic> json) {
    return GameQuestion(
      id: json['id'] as String,
      category: json['category'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      difficulty: json['difficulty'] as String? ?? 'medium',
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'question': question,
      'answer': answer,
      'difficulty': difficulty,
      'last_used_at': lastUsedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'category': category,
      'question': question,
      'answer': answer,
      'difficulty': difficulty,
    };
  }

  GameQuestion copyWith({
    String? id,
    String? category,
    String? question,
    String? answer,
    String? difficulty,
    DateTime? lastUsedAt,
    DateTime? createdAt,
  }) {
    return GameQuestion(
      id: id ?? this.id,
      category: category ?? this.category,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      difficulty: difficulty ?? this.difficulty,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
