import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/true_false_question.dart';

/// Service for managing true/false questions
/// Uses per-user tracking via user_true_false_history table
class TrueFalseService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'true_false_questions';
  static const String _historyTable = 'user_true_false_history';

  /// Get the next true/false question (prioritizes unseen, then oldest seen)
  /// If difficulty is provided, filters by difficulty level
  /// If excludeIds is provided, skips questions with those IDs (for current session)
  static Future<TrueFalseQuestion?> getNextQuestion({
    String? difficulty,
    Set<String>? excludeIds,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('TrueFalseService: No user logged in');
        return null;
      }

      // Get user's question history
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

      // Build query for questions
      var query = _supabase.from(_tableName).select();

      // Apply difficulty filter if provided
      if (difficulty != null && difficulty.isNotEmpty) {
        query = query.eq('difficulty', difficulty);
      }

      final questionsResponse = await query;

      if (questionsResponse.isEmpty) {
        debugPrint(
            'TrueFalseService: No questions found (difficulty: $difficulty)');
        return null;
      }

      // Filter out excluded IDs (already asked this session)
      final filteredQuestions = excludeIds != null && excludeIds.isNotEmpty
          ? questionsResponse
              .where((q) => !excludeIds.contains(q['id'] as String))
              .toList()
          : questionsResponse;

      if (filteredQuestions.isEmpty) {
        debugPrint('TrueFalseService: All questions already asked this session');
        return null;
      }

      // Sort: questions not in history first (never seen), then by oldest seen
      filteredQuestions.sort((a, b) {
        final aUsed = historyMap[a['id'] as String];
        final bUsed = historyMap[b['id'] as String];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1; // a comes first (never used)
        if (bUsed == null) return 1; // b comes first (never used)
        return aUsed.compareTo(bUsed); // older usage comes first
      });

      final question = TrueFalseQuestion.fromJson(filteredQuestions.first);
      debugPrint(
          'TrueFalseService: Got question ${question.id} (difficulty: ${question.difficulty}) for user $userId');
      return question;
    } catch (e) {
      debugPrint('TrueFalseService: Error getting question: $e');
      return null;
    }
  }

  /// Mark a question as used for the current user
  static Future<void> markAsUsed(String questionId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('TrueFalseService: No user logged in, cannot mark as used');
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
          'TrueFalseService: Marked $questionId as used for user $userId');
    } catch (e) {
      debugPrint('TrueFalseService: Error marking as used: $e');
    }
  }

  /// Get count of true/false questions by difficulty
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

      debugPrint('TrueFalseService: Question counts: $counts');
      return counts;
    } catch (e) {
      debugPrint('TrueFalseService: Error getting counts: $e');
      return {'easy': 0, 'medium': 0, 'hard': 0};
    }
  }
}
