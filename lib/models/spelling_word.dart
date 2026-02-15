/// A spelling word for the spelling quiz
class SpellingWord {
  final String id;
  final String word;
  final String difficulty; // 'easy', 'medium', 'hard'
  final DateTime createdAt;

  const SpellingWord({
    required this.id,
    required this.word,
    required this.difficulty,
    required this.createdAt,
  });

  factory SpellingWord.fromJson(Map<String, dynamic> json) {
    return SpellingWord(
      id: json['id'] as String,
      word: json['word'] as String,
      difficulty: json['difficulty'] as String? ?? 'medium',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'word': word,
      'difficulty': difficulty,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
