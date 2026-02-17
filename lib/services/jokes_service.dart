import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/joke.dart';

/// Service for managing jokes
/// Uses per-user tracking via user_jokes_history table
class JokesService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'jokes';
  static const String _historyTable = 'user_jokes_history';

  /// Get the next joke (prioritizes unseen, then oldest seen)
  /// If difficulty is provided, filters by difficulty level
  /// If excludeIds is provided, skips jokes with those IDs (for current session)
  static Future<Joke?> getNextQuestion({
    String? difficulty,
    Set<String>? excludeIds,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('JokesService: No user logged in');
        return null;
      }

      // Get user's joke history
      final historyResponse = await _supabase
          .from(_historyTable)
          .select('question_id, last_used_at')
          .eq('user_id', userId);

      // Build a map of question_id -> last_used_at
      final historyMap = <String, DateTime>{};
      for (final row in historyResponse) {
        historyMap[row['question_id'] as String] =
            DateTime.parse(row['last_used_at'] as String);
      }

      // Build query for jokes
      var query = _supabase.from(_tableName).select();

      // Apply difficulty filter if provided
      if (difficulty != null && difficulty.isNotEmpty) {
        query = query.eq('difficulty', difficulty);
      }

      final jokesResponse = await query;

      if (jokesResponse.isEmpty) {
        debugPrint('JokesService: No jokes found (difficulty: $difficulty)');
        return null;
      }

      // Filter out excluded IDs (already asked this session)
      final filteredJokes = excludeIds != null && excludeIds.isNotEmpty
          ? jokesResponse
              .where((j) => !excludeIds.contains(j['id'] as String))
              .toList()
          : jokesResponse;

      if (filteredJokes.isEmpty) {
        debugPrint('JokesService: All jokes already asked this session');
        return null;
      }

      // Sort: jokes not in history first (never seen), then by oldest seen
      filteredJokes.sort((a, b) {
        final aUsed = historyMap[a['id'] as String];
        final bUsed = historyMap[b['id'] as String];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1; // a comes first (never used)
        if (bUsed == null) return 1; // b comes first (never used)
        return aUsed.compareTo(bUsed); // older usage comes first
      });

      final joke = Joke.fromJson(filteredJokes.first);
      debugPrint(
          'JokesService: Got joke ${joke.id} (difficulty: ${joke.difficulty}) for user $userId');
      return joke;
    } catch (e) {
      debugPrint('JokesService: Error getting joke: $e');
      return null;
    }
  }

  /// Mark a joke as used for the current user
  static Future<void> markAsUsed(String questionId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('JokesService: No user logged in, cannot mark as used');
        return;
      }

      await _supabase.from(_historyTable).upsert(
        {
          'user_id': userId,
          'question_id': questionId,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,question_id',
      );
      debugPrint('JokesService: Marked $questionId as used for user $userId');
    } catch (e) {
      debugPrint('JokesService: Error marking as used: $e');
    }
  }

  /// Get count of jokes by difficulty
  static Future<Map<String, int>> getQuestionCounts() async {
    try {
      final response = await _supabase.from(_tableName).select('difficulty');

      final counts = <String, int>{
        'easy': 0,
        'medium': 0,
        'hard': 0,
      };

      for (final row in response) {
        final difficulty = row['difficulty'] as String;
        counts[difficulty] = (counts[difficulty] ?? 0) + 1;
      }

      debugPrint('JokesService: Joke counts: $counts');
      return counts;
    } catch (e) {
      debugPrint('JokesService: Error getting counts: $e');
      return {'easy': 0, 'medium': 0, 'hard': 0};
    }
  }
}
