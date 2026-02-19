import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A geography problem for the US States quiz/lessons
class GeographyProblem {
  final String id;
  final String answer; // State name
  final List<String> aliases;
  final String hint; // Quiz hint or lesson narration
  final String stateId; // Two-letter abbreviation (e.g., "CA")
  final String capital;
  final String region;
  final String? nickname;

  const GeographyProblem({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.hint,
    required this.stateId,
    required this.capital,
    required this.region,
    this.nickname,
  });
}

/// Service for generating US Geography quiz/lesson content
/// Uses local JSON data with shared_preferences for history tracking
class GeographyService {
  static List<_StateData>? _cachedStates;
  static const String _historyKey = 'geography_history';

  /// Load states from JSON asset (cached after first load)
  static Future<void> _ensureLoaded() async {
    if (_cachedStates != null) return;

    try {
      final jsonString =
          await rootBundle.loadString('assets/data/us_states.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final statesList = jsonData['states'] as List<dynamic>;

      _cachedStates = statesList.map((s) {
        final stateId = s['id'] as String;
        final name = s['name'] as String;
        final capital = s['capital'] as String;
        final region = s['region'] as String;
        final nickname = s['nickname'] as String?;
        final funFacts = (s['fun_facts'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        // Build lesson narration
        final lessonNarration = _buildLessonNarration(
          name: name,
          capital: capital,
          region: region,
          nickname: nickname,
          funFacts: funFacts,
        );

        // Quiz hint: Don't reveal the name, give description
        final quizHint = _buildQuizHint(
          capital: capital,
          region: region,
          nickname: nickname,
          funFacts: funFacts,
        );

        return _StateData(
          id: stateId,
          answer: name,
          aliases: [
            name.toLowerCase(),
            stateId.toLowerCase(),
            stateId.toUpperCase(),
          ],
          quizHint: quizHint,
          lessonHint: lessonNarration,
          stateId: stateId,
          capital: capital,
          region: region,
          nickname: nickname,
        );
      }).toList();

      debugPrint('GeographyService: Loaded ${_cachedStates!.length} states');
    } catch (e) {
      debugPrint('GeographyService: Error loading states: $e');
      _cachedStates = [];
    }
  }

  /// Build lesson narration text
  static String _buildLessonNarration({
    required String name,
    required String capital,
    required String region,
    String? nickname,
    List<String>? funFacts,
  }) {
    final buffer = StringBuffer();

    // Introduction with nickname
    if (nickname != null) {
      buffer.write('This is $name, also known as $nickname. ');
    } else {
      buffer.write('This is $name. ');
    }

    // Capital and region
    buffer.write('Its capital is $capital. ');
    buffer.write('$name is located in the $region region of the United States. ');

    // Fun fact
    if (funFacts != null && funFacts.isNotEmpty) {
      buffer.write('Here\'s a fun fact: ${funFacts.first} ');
    }

    // End with prompt
    buffer.write('Can you say $name?');

    return buffer.toString();
  }

  /// Build quiz hint text (don't reveal name)
  static String _buildQuizHint({
    required String capital,
    required String region,
    String? nickname,
    List<String>? funFacts,
  }) {
    final buffer = StringBuffer();

    // Give clues without revealing the name
    buffer.write('This state is in the $region. ');
    buffer.write('Its capital is $capital. ');

    if (nickname != null) {
      buffer.write('It\'s known as $nickname. ');
    } else if (funFacts != null && funFacts.isNotEmpty) {
      // Use a fun fact as a hint
      buffer.write('${funFacts.first} ');
    }

    buffer.write('What state is this?');

    return buffer.toString();
  }

  /// Generate a random state quiz problem (prioritizes unseen, then oldest seen)
  static Future<GeographyProblem?> generate({Set<String>? excludeIds}) async {
    try {
      await _ensureLoaded();

      if (_cachedStates == null || _cachedStates!.isEmpty) {
        return null;
      }

      // Get history from shared preferences
      final historyMap = await _getHistory();

      // Filter out excluded IDs (already asked this session)
      var available = _cachedStates!
          .where((s) => excludeIds == null || !excludeIds.contains(s.id))
          .toList();

      if (available.isEmpty) {
        return null;
      }

      // Sort: states not in history first (never seen), then by oldest seen
      available.sort((a, b) {
        final aUsed = historyMap[a.id];
        final bUsed = historyMap[b.id];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1;
        if (bUsed == null) return 1;
        return aUsed.compareTo(bUsed);
      });

      final state = available.first;

      return GeographyProblem(
        id: state.id,
        answer: state.answer,
        aliases: state.aliases,
        hint: state.quizHint,
        stateId: state.stateId,
        capital: state.capital,
        region: state.region,
        nickname: state.nickname,
      );
    } catch (e) {
      debugPrint('GeographyService: Error generating state: $e');
      return null;
    }
  }

  /// Generate a random state lesson (prioritizes unseen, then oldest seen)
  static Future<GeographyProblem?> generateLesson({Set<String>? excludeIds}) async {
    try {
      await _ensureLoaded();

      if (_cachedStates == null || _cachedStates!.isEmpty) {
        return null;
      }

      // Get history from shared preferences
      final historyMap = await _getHistory();

      // Filter out excluded IDs (already asked this session)
      var available = _cachedStates!
          .where((s) => excludeIds == null || !excludeIds.contains(s.id))
          .toList();

      if (available.isEmpty) {
        return null;
      }

      // Sort: states not in history first (never seen), then by oldest seen
      available.sort((a, b) {
        final aUsed = historyMap[a.id];
        final bUsed = historyMap[b.id];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1;
        if (bUsed == null) return 1;
        return aUsed.compareTo(bUsed);
      });

      final state = available.first;

      return GeographyProblem(
        id: state.id,
        answer: state.answer,
        aliases: state.aliases,
        hint: state.lessonHint,
        stateId: state.stateId,
        capital: state.capital,
        region: state.region,
        nickname: state.nickname,
      );
    } catch (e) {
      debugPrint('GeographyService: Error generating state lesson: $e');
      return null;
    }
  }

  /// Mark a state as used
  static Future<void> markAsUsed(String stateId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);

      Map<String, String> history = {};
      if (historyJson != null) {
        final decoded = json.decode(historyJson) as Map<String, dynamic>;
        history = decoded.map((k, v) => MapEntry(k, v as String));
      }

      history[stateId] = DateTime.now().toIso8601String();

      await prefs.setString(_historyKey, json.encode(history));
      debugPrint('GeographyService: Marked $stateId as used');
    } catch (e) {
      debugPrint('GeographyService: Error marking as used: $e');
    }
  }

  /// Get history from shared preferences
  static Future<Map<String, DateTime>> _getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);

      if (historyJson == null) return {};

      final decoded = json.decode(historyJson) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
    } catch (e) {
      debugPrint('GeographyService: Error getting history: $e');
      return {};
    }
  }

  /// Get total number of states available
  static Future<int> get totalStates async {
    await _ensureLoaded();
    return _cachedStates?.length ?? 0;
  }

  /// Clear cache (for testing)
  static void clearCache() {
    _cachedStates = null;
  }
}

/// Internal state data class
class _StateData {
  final String id;
  final String answer;
  final List<String> aliases;
  final String quizHint;
  final String lessonHint;
  final String stateId;
  final String capital;
  final String region;
  final String? nickname;

  const _StateData({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.quizHint,
    required this.lessonHint,
    required this.stateId,
    required this.capital,
    required this.region,
    this.nickname,
  });
}
