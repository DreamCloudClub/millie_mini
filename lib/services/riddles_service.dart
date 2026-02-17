import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/riddle.dart';

/// Service for managing riddles
/// Uses per-user tracking via user_riddles_history table
class RiddlesService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'riddles';
  static const String _historyTable = 'user_riddles_history';

  /// Get the next riddle (prioritizes unseen, then oldest seen)
  /// If difficulty is provided, filters by difficulty level
  /// If excludeIds is provided, skips riddles with those IDs (for current session)
  static Future<Riddle?> getNextQuestion({
    String? difficulty,
    Set<String>? excludeIds,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('RiddlesService: No user logged in');
        return null;
      }

      // Get user's riddle history
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

      // Build query for riddles
      var query = _supabase.from(_tableName).select();

      // Apply difficulty filter if provided
      if (difficulty != null && difficulty.isNotEmpty) {
        query = query.eq('difficulty', difficulty);
      }

      final riddlesResponse = await query;

      if (riddlesResponse.isEmpty) {
        debugPrint(
            'RiddlesService: No riddles found (difficulty: $difficulty)');
        return null;
      }

      // Filter out excluded IDs (already asked this session)
      final filteredRiddles = excludeIds != null && excludeIds.isNotEmpty
          ? riddlesResponse
              .where((r) => !excludeIds.contains(r['id'] as String))
              .toList()
          : riddlesResponse;

      if (filteredRiddles.isEmpty) {
        debugPrint('RiddlesService: All riddles already asked this session');
        return null;
      }

      // Sort: riddles not in history first (never seen), then by oldest seen
      filteredRiddles.sort((a, b) {
        final aUsed = historyMap[a['id'] as String];
        final bUsed = historyMap[b['id'] as String];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1; // a comes first (never used)
        if (bUsed == null) return 1; // b comes first (never used)
        return aUsed.compareTo(bUsed); // older usage comes first
      });

      final riddle = Riddle.fromJson(filteredRiddles.first);
      debugPrint(
          'RiddlesService: Got riddle ${riddle.id} (difficulty: ${riddle.difficulty}) for user $userId');
      return riddle;
    } catch (e) {
      debugPrint('RiddlesService: Error getting riddle: $e');
      return null;
    }
  }

  /// Mark a riddle as used for the current user
  static Future<void> markAsUsed(String questionId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('RiddlesService: No user logged in, cannot mark as used');
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
      debugPrint(
          'RiddlesService: Marked $questionId as used for user $userId');
    } catch (e) {
      debugPrint('RiddlesService: Error marking as used: $e');
    }
  }

  /// Get count of riddles by difficulty
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

      debugPrint('RiddlesService: Riddle counts: $counts');
      return counts;
    } catch (e) {
      debugPrint('RiddlesService: Error getting counts: $e');
      return {'easy': 0, 'medium': 0, 'hard': 0};
    }
  }
}
