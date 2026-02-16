/// A user-defined custom quiz mix
class CustomQuiz {
  final String id;
  final String userId;
  final String name;
  final List<String> categories; // ['riddle', 'spelling', 'trivia', 'joke']
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomQuiz({
    required this.id,
    required this.userId,
    required this.name,
    required this.categories,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomQuiz.fromJson(Map<String, dynamic> json) {
    return CustomQuiz(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      categories: (json['categories'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'categories': categories,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'name': name,
      'categories': categories,
    };
  }

  CustomQuiz copyWith({
    String? id,
    String? userId,
    String? name,
    List<String>? categories,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomQuiz(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      categories: categories ?? this.categories,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get display text for categories
  String get categoriesDisplay {
    return categories.map((c) => _categoryDisplayName(c)).join(' • ');
  }

  static String _categoryDisplayName(String category) {
    switch (category) {
      case 'riddle':
        return 'Riddles';
      case 'joke':
        return 'Jokes';
      case 'trivia':
        return 'Trivia';
      case 'spelling':
        return 'Spelling';
      case 'math':
        return 'Math';
      default:
        return category;
    }
  }
}
