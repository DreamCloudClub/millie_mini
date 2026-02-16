import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/game_question.dart';

/// Service for managing game questions (riddles, jokes, trivia)
/// Uses per-user tracking via user_question_history table
class GameQuestionsService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'game_questions';
  static const String _historyTable = 'user_question_history';

  /// Get the next question for a category (prioritizes unseen, then oldest seen)
  /// If category is 'random', picks from any category
  /// If difficulty is provided, filters by difficulty level
  /// If excludeIds is provided, skips questions with those IDs (for current session)
  /// Tracks usage per authenticated user
  static Future<GameQuestion?> getNextQuestion(
    String category, {
    String? difficulty,
    Set<String>? excludeIds,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('GameQuestionsService: No user logged in');
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

      // Apply category filter if not random
      if (category != 'random') {
        query = query.eq('category', category);
      }

      // Apply difficulty filter if provided
      if (difficulty != null && difficulty.isNotEmpty) {
        query = query.eq('difficulty', difficulty);
      }

      final questionsResponse = await query;

      if (questionsResponse.isEmpty) {
        debugPrint('GameQuestionsService: No questions found for $category (difficulty: $difficulty)');
        return null;
      }

      // Filter out excluded IDs (already asked this session)
      final filteredQuestions = excludeIds != null && excludeIds.isNotEmpty
          ? questionsResponse.where((q) => !excludeIds.contains(q['id'] as String)).toList()
          : questionsResponse;

      if (filteredQuestions.isEmpty) {
        debugPrint('GameQuestionsService: All questions already asked this session');
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

      final question =
          GameQuestion.fromJson(filteredQuestions.first as Map<String, dynamic>);
      debugPrint(
          'GameQuestionsService: Got question ${question.id} (${question.category}, difficulty: ${question.difficulty}) for user $userId');
      return question;
    } catch (e) {
      debugPrint('GameQuestionsService: Error getting question: $e');
      return null;
    }
  }

  /// Mark a question as used for the current user (upserts to user_question_history)
  static Future<void> markAsUsed(String questionId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('GameQuestionsService: No user logged in, cannot mark as used');
        return;
      }

      // Use upsert with explicit conflict columns for composite primary key
      await _supabase.from(_historyTable).upsert(
        {
          'user_id': userId,
          'question_id': questionId,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,question_id',
      );
      debugPrint(
          'GameQuestionsService: Marked $questionId as used for user $userId');
    } catch (e) {
      debugPrint('GameQuestionsService: Error marking as used: $e');
    }
  }

  /// Get count of questions by category
  static Future<Map<String, int>> getQuestionCounts() async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select('category');

      final counts = <String, int>{
        'riddle': 0,
        'joke': 0,
        'trivia': 0,
      };

      for (final row in response) {
        final category = row['category'] as String;
        counts[category] = (counts[category] ?? 0) + 1;
      }

      debugPrint('GameQuestionsService: Question counts: $counts');
      return counts;
    } catch (e) {
      debugPrint('GameQuestionsService: Error getting counts: $e');
      return {'riddle': 0, 'joke': 0, 'trivia': 0};
    }
  }

  /// Add a new question
  static Future<GameQuestion?> addQuestion({
    required String category,
    required String question,
    required String answer,
    String difficulty = 'medium',
  }) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .insert({
            'category': category,
            'question': question,
            'answer': answer,
            'difficulty': difficulty,
          })
          .select()
          .single();

      final created = GameQuestion.fromJson(response);
      debugPrint('GameQuestionsService: Added question ${created.id}');
      return created;
    } catch (e) {
      debugPrint('GameQuestionsService: Error adding question: $e');
      return null;
    }
  }

  /// Bulk add questions
  static Future<int> addQuestions(List<Map<String, String>> questions) async {
    try {
      final data = questions.map((q) => {
        'category': q['category'],
        'question': q['question'],
        'answer': q['answer'],
      }).toList();

      await _supabase.from(_tableName).insert(data);
      debugPrint('GameQuestionsService: Added ${questions.length} questions');
      return questions.length;
    } catch (e) {
      debugPrint('GameQuestionsService: Error bulk adding: $e');
      return 0;
    }
  }
}
