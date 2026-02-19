/// Data model for a U.S. State used in Geography lessons
/// Designed to support both local JSON and future Supabase migration
class USState {
  /// Two-letter state abbreviation (e.g., "CA", "TX")
  final String id;

  /// Full state name (e.g., "California")
  final String name;

  /// State capital city
  final String capital;

  /// Geographic region (Northeast, South, Midwest, West)
  final String region;

  /// Year the state was admitted to the Union
  final int? statehoodYear;

  /// Approximate population (can be null)
  final int? population;

  /// List of 2-3 fun facts about the state
  final List<String> funFacts;

  /// SVG path ID used in the US map (usually same as id)
  final String mapPathId;

  /// Asset path to the state silhouette SVG
  final String silhouetteAssetPath;

  /// Asset path to the state flag image (PNG or SVG)
  final String? flagAssetPath;

  /// Nickname for the state (e.g., "The Golden State")
  final String? nickname;

  USState({
    required this.id,
    required this.name,
    required this.capital,
    required this.region,
    this.statehoodYear,
    this.population,
    required this.funFacts,
    String? mapPathId,
    String? silhouetteAssetPath,
    this.flagAssetPath,
    this.nickname,
  })  : mapPathId = mapPathId ?? id.toLowerCase(),
        silhouetteAssetPath =
            silhouetteAssetPath ?? 'assets/svg/states/${id.toLowerCase()}.svg';

  /// Create from JSON map
  factory USState.fromJson(Map<String, dynamic> json) {
    return USState(
      id: json['id'] as String,
      name: json['name'] as String,
      capital: json['capital'] as String,
      region: json['region'] as String,
      statehoodYear: json['statehood_year'] as int?,
      population: json['population'] as int?,
      funFacts: (json['fun_facts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      mapPathId: json['map_path_id'] as String?,
      silhouetteAssetPath: json['silhouette_asset_path'] as String?,
      flagAssetPath: json['flag_asset_path'] as String?,
      nickname: json['nickname'] as String?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'capital': capital,
      'region': region,
      'statehood_year': statehoodYear,
      'population': population,
      'fun_facts': funFacts,
      'map_path_id': mapPathId,
      'silhouette_asset_path': silhouetteAssetPath,
      'flag_asset_path': flagAssetPath,
      'nickname': nickname,
    };
  }

  /// Get a short introduction for TTS
  String get introText {
    final nicknamePart = nickname != null ? ', also known as $nickname,' : '';
    return 'This is $name$nicknamePart. Its capital is $capital.';
  }

  /// Get the full lesson narration
  String get narrationText {
    final buffer = StringBuffer();
    buffer.write(introText);
    buffer.write(' $name is located in the $region region of the United States.');
    if (statehoodYear != null) {
      buffer.write(' It became a state in $statehoodYear.');
    }
    if (funFacts.isNotEmpty) {
      buffer.write(' Here\'s a fun fact: ${funFacts.first}');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'USState($id: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is USState && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Quiz question types for state quizzes
enum StateQuizType {
  capital, // "What is the capital of [State]?"
  stateFromCapital, // "Which state has [Capital] as its capital?"
  region, // "What region is [State] in?"
  abbreviation, // "What is the abbreviation for [State]?"
  identify, // Show map, ask to identify highlighted state
}

/// A quiz question about a state
class StateQuizQuestion {
  final USState state;
  final StateQuizType type;
  final String question;
  final String correctAnswer;
  final List<String> choices; // For multiple choice

  StateQuizQuestion({
    required this.state,
    required this.type,
    required this.question,
    required this.correctAnswer,
    required this.choices,
  });

  /// Generate a capital question
  factory StateQuizQuestion.capital(USState state, List<String> otherCapitals) {
    final choices = [state.capital, ...otherCapitals.take(3)]..shuffle();
    return StateQuizQuestion(
      state: state,
      type: StateQuizType.capital,
      question: 'What is the capital of ${state.name}?',
      correctAnswer: state.capital,
      choices: choices,
    );
  }

  /// Generate a state identification question
  factory StateQuizQuestion.identify(USState state, List<String> otherStates) {
    final choices = [state.name, ...otherStates.take(3)]..shuffle();
    return StateQuizQuestion(
      state: state,
      type: StateQuizType.identify,
      question: 'Which state is highlighted on the map?',
      correctAnswer: state.name,
      choices: choices,
    );
  }

  /// Generate an abbreviation question
  factory StateQuizQuestion.abbreviation(
      USState state, List<String> otherAbbreviations) {
    final choices = [state.id, ...otherAbbreviations.take(3)]..shuffle();
    return StateQuizQuestion(
      state: state,
      type: StateQuizType.abbreviation,
      question: 'What is the two-letter abbreviation for ${state.name}?',
      correctAnswer: state.id,
      choices: choices,
    );
  }
}

/// Progress tracking for a user's geography learning
class GeographyProgress {
  /// Map of state ID to number of times seen in browse mode
  final Map<String, int> statesSeenCount;

  /// Queue of recently seen state IDs (for avoiding repeats)
  final List<String> recentlySeenStates;

  /// Map of state ID to quiz statistics
  final Map<String, StateQuizStats> quizStats;

  /// Maximum size of recently seen queue
  static const int maxRecentlySeenSize = 10;

  GeographyProgress({
    Map<String, int>? statesSeenCount,
    List<String>? recentlySeenStates,
    Map<String, StateQuizStats>? quizStats,
  })  : statesSeenCount = statesSeenCount ?? {},
        recentlySeenStates = recentlySeenStates ?? [],
        quizStats = quizStats ?? {};

  /// Record that a state was seen
  void recordStateSeen(String stateId) {
    statesSeenCount[stateId] = (statesSeenCount[stateId] ?? 0) + 1;

    // Add to recently seen, removing oldest if at capacity
    recentlySeenStates.remove(stateId); // Remove if already present
    recentlySeenStates.add(stateId);
    while (recentlySeenStates.length > maxRecentlySeenSize) {
      recentlySeenStates.removeAt(0);
    }
  }

  /// Record a quiz answer
  void recordQuizAnswer(String stateId, bool correct) {
    final stats = quizStats[stateId] ?? StateQuizStats();
    quizStats[stateId] = StateQuizStats(
      correctCount: stats.correctCount + (correct ? 1 : 0),
      totalCount: stats.totalCount + 1,
    );
  }

  /// Check if a state was recently seen
  bool wasRecentlySeen(String stateId) {
    return recentlySeenStates.contains(stateId);
  }

  /// Create from JSON
  factory GeographyProgress.fromJson(Map<String, dynamic> json) {
    return GeographyProgress(
      statesSeenCount: (json['states_seen_count'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as int)),
      recentlySeenStates: (json['recently_seen_states'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      quizStats: (json['quiz_stats'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, StateQuizStats.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'states_seen_count': statesSeenCount,
      'recently_seen_states': recentlySeenStates,
      'quiz_stats': quizStats.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
}

/// Quiz statistics for a single state
class StateQuizStats {
  final int correctCount;
  final int totalCount;

  StateQuizStats({
    this.correctCount = 0,
    this.totalCount = 0,
  });

  double get accuracy => totalCount > 0 ? correctCount / totalCount : 0.0;

  factory StateQuizStats.fromJson(Map<String, dynamic> json) {
    return StateQuizStats(
      correctCount: json['correct_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'correct_count': correctCount,
      'total_count': totalCount,
    };
  }
}
