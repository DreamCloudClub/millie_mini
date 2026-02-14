/// A game question (riddle, joke, or trivia)
class GameQuestion {
  final String id;
  final String category; // 'riddle', 'joke', 'trivia'
  final String question;
  final String answer;
  final DateTime? lastUsedAt;
  final DateTime createdAt;

  const GameQuestion({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    this.lastUsedAt,
    required this.createdAt,
  });

  factory GameQuestion.fromJson(Map<String, dynamic> json) {
    return GameQuestion(
      id: json['id'] as String,
      category: json['category'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
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
      'last_used_at': lastUsedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'category': category,
      'question': question,
      'answer': answer,
    };
  }

  GameQuestion copyWith({
    String? id,
    String? category,
    String? question,
    String? answer,
    DateTime? lastUsedAt,
    DateTime? createdAt,
  }) {
    return GameQuestion(
      id: id ?? this.id,
      category: category ?? this.category,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
