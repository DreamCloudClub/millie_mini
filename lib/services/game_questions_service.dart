import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/game_question.dart';

/// Service for managing game questions (riddles, jokes, trivia)
class GameQuestionsService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'game_questions';

  /// Get the next question for a category (oldest last_used_at first)
  /// If category is 'random', picks from any category
  static Future<GameQuestion?> getNextQuestion(String category) async {
    try {
      final query = _supabase.from(_tableName).select();

      List<dynamic> response;
      if (category == 'random') {
        // Get oldest used from any category
        response = await query
            .order('last_used_at', ascending: true, nullsFirst: true)
            .limit(1);
      } else {
        // Get oldest used from specific category
        response = await query
            .eq('category', category)
            .order('last_used_at', ascending: true, nullsFirst: true)
            .limit(1);
      }

      if (response.isEmpty) {
        debugPrint('GameQuestionsService: No questions found for $category');
        return null;
      }

      final question = GameQuestion.fromJson(response.first as Map<String, dynamic>);
      debugPrint('GameQuestionsService: Got question ${question.id} (${question.category})');
      return question;
    } catch (e) {
      debugPrint('GameQuestionsService: Error getting question: $e');
      return null;
    }
  }

  /// Mark a question as used (updates last_used_at)
  static Future<void> markAsUsed(String questionId) async {
    try {
      await _supabase
          .from(_tableName)
          .update({'last_used_at': DateTime.now().toIso8601String()})
          .eq('id', questionId);
      debugPrint('GameQuestionsService: Marked $questionId as used');
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
  }) async {
    try {
      final response = await _supabase
          .from(_tableName)
          .insert({
            'category': category,
            'question': question,
            'answer': answer,
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
