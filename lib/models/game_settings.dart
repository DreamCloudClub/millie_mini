/// Time limit options for game questions
enum TimeLimit { none, ten, twenty, thirty }

/// Difficulty levels for game questions
enum GameDifficulty { easy, medium, hard }

extension TimeLimitExtension on TimeLimit {
  /// Display name for UI
  String get displayName {
    switch (this) {
      case TimeLimit.none:
        return 'None';
      case TimeLimit.ten:
        return '10 seconds';
      case TimeLimit.twenty:
        return '20 seconds';
      case TimeLimit.thirty:
        return '30 seconds';
    }
  }

  /// Seconds value (null for none)
  int? get seconds {
    switch (this) {
      case TimeLimit.none:
        return null;
      case TimeLimit.ten:
        return 10;
      case TimeLimit.twenty:
        return 20;
      case TimeLimit.thirty:
        return 30;
    }
  }

  /// Create from string value
  static TimeLimit fromString(String? value) {
    switch (value) {
      case 'ten':
        return TimeLimit.ten;
      case 'twenty':
        return TimeLimit.twenty;
      case 'thirty':
        return TimeLimit.thirty;
      default:
        return TimeLimit.none;
    }
  }
}

extension GameDifficultyExtension on GameDifficulty {
  /// Display name for UI
  String get displayName {
    switch (this) {
      case GameDifficulty.easy:
        return 'Easy';
      case GameDifficulty.medium:
        return 'Medium';
      case GameDifficulty.hard:
        return 'Hard';
    }
  }

  /// Database value
  String get dbValue {
    switch (this) {
      case GameDifficulty.easy:
        return 'easy';
      case GameDifficulty.medium:
        return 'medium';
      case GameDifficulty.hard:
        return 'hard';
    }
  }

  /// Create from string value
  static GameDifficulty fromString(String? value) {
    switch (value) {
      case 'easy':
        return GameDifficulty.easy;
      case 'hard':
        return GameDifficulty.hard;
      default:
        return GameDifficulty.medium;
    }
  }
}

/// Game settings model for time limits and difficulty
class GameSettings {
  final TimeLimit timeLimit;
  final GameDifficulty difficulty;

  const GameSettings({
    this.timeLimit = TimeLimit.none,
    this.difficulty = GameDifficulty.medium,
  });

  /// Default settings
  static const GameSettings defaults = GameSettings();

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    return GameSettings(
      timeLimit: TimeLimitExtension.fromString(json['time_limit'] as String?),
      difficulty: GameDifficultyExtension.fromString(json['difficulty'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'time_limit': timeLimit.name,
      'difficulty': difficulty.name,
    };
  }

  GameSettings copyWith({
    TimeLimit? timeLimit,
    GameDifficulty? difficulty,
  }) {
    return GameSettings(
      timeLimit: timeLimit ?? this.timeLimit,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameSettings &&
        other.timeLimit == timeLimit &&
        other.difficulty == difficulty;
  }

  @override
  int get hashCode => timeLimit.hashCode ^ difficulty.hashCode;

  @override
  String toString() {
    return 'GameSettings(timeLimit: ${timeLimit.displayName}, difficulty: ${difficulty.displayName})';
  }
}
