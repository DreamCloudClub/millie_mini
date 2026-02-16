import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/custom_quiz.dart';

/// Provider for managing custom quiz mixes
class CustomQuizProvider extends ChangeNotifier {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'custom_quizzes';

  List<CustomQuiz> _quizzes = [];
  bool _isLoading = false;
  String? _error;

  List<CustomQuiz> get quizzes => _quizzes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all custom quizzes for the current user
  Future<void> loadQuizzes() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('CustomQuizProvider: No user logged in');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      _quizzes = (response as List)
          .map((json) => CustomQuiz.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('CustomQuizProvider: Loaded ${_quizzes.length} quizzes');
    } catch (e) {
      debugPrint('CustomQuizProvider: Error loading quizzes: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get a quiz by ID
  CustomQuiz? getQuizById(String id) {
    try {
      return _quizzes.firstWhere((q) => q.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Create a new custom quiz
  Future<CustomQuiz?> createQuiz({
    required String name,
    required List<String> categories,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('CustomQuizProvider: No user logged in');
      return null;
    }

    try {
      final response = await _supabase
          .from(_tableName)
          .insert({
            'user_id': userId,
            'name': name,
            'categories': categories,
          })
          .select()
          .single();

      final quiz = CustomQuiz.fromJson(response);
      _quizzes.add(quiz);
      notifyListeners();

      debugPrint('CustomQuizProvider: Created quiz ${quiz.id}');
      return quiz;
    } catch (e) {
      debugPrint('CustomQuizProvider: Error creating quiz: $e');
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Update an existing quiz
  Future<bool> updateQuiz({
    required String quizId,
    required String name,
    required List<String> categories,
  }) async {
    try {
      await _supabase
          .from(_tableName)
          .update({
            'name': name,
            'categories': categories,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', quizId);

      // Update local list
      final index = _quizzes.indexWhere((q) => q.id == quizId);
      if (index >= 0) {
        _quizzes[index] = _quizzes[index].copyWith(
          name: name,
          categories: categories,
          updatedAt: DateTime.now(),
        );
        notifyListeners();
      }

      debugPrint('CustomQuizProvider: Updated quiz $quizId');
      return true;
    } catch (e) {
      debugPrint('CustomQuizProvider: Error updating quiz: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a quiz
  Future<bool> deleteQuiz(String quizId) async {
    try {
      await _supabase.from(_tableName).delete().eq('id', quizId);

      _quizzes.removeWhere((q) => q.id == quizId);
      notifyListeners();

      debugPrint('CustomQuizProvider: Deleted quiz $quizId');
      return true;
    } catch (e) {
      debugPrint('CustomQuizProvider: Error deleting quiz: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
