import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/spelling_word.dart';

/// Service for managing spelling words
/// Uses per-user tracking via user_spelling_history table
class SpellingWordsService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'spelling_words';
  static const String _historyTable = 'user_spelling_history';

  /// Get the next spelling word (prioritizes unseen, then oldest seen)
  /// If difficulty is provided, filters by difficulty level
  /// If excludeIds is provided, skips words with those IDs (for current session)
  static Future<SpellingWord?> getNextWord({
    String? difficulty,
    Set<String>? excludeIds,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('SpellingWordsService: No user logged in');
        return null;
      }

      // Get user's word history
      final historyResponse = await _supabase
          .from(_historyTable)
          .select('word_id, last_used_at')
          .eq('user_id', userId);

      // Build a map of word_id -> last_used_at
      final historyMap = <String, DateTime>{};
      for (final row in historyResponse) {
        historyMap[row['word_id'] as String] =
            DateTime.parse(row['last_used_at'] as String);
      }

      // Build query for words
      var query = _supabase.from(_tableName).select();

      // Apply difficulty filter if provided
      if (difficulty != null && difficulty.isNotEmpty) {
        query = query.eq('difficulty', difficulty);
      }

      final wordsResponse = await query;

      if (wordsResponse.isEmpty) {
        debugPrint(
            'SpellingWordsService: No words found (difficulty: $difficulty)');
        return null;
      }

      // Filter out excluded IDs (already asked this session)
      final filteredWords = excludeIds != null && excludeIds.isNotEmpty
          ? wordsResponse.where((w) => !excludeIds.contains(w['id'] as String)).toList()
          : wordsResponse;

      if (filteredWords.isEmpty) {
        debugPrint('SpellingWordsService: All words already asked this session');
        return null;
      }

      // Sort: words not in history first (never seen), then by oldest seen
      filteredWords.sort((a, b) {
        final aUsed = historyMap[a['id'] as String];
        final bUsed = historyMap[b['id'] as String];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1; // a comes first (never used)
        if (bUsed == null) return 1; // b comes first (never used)
        return aUsed.compareTo(bUsed); // older usage comes first
      });

      final word = SpellingWord.fromJson(filteredWords.first);
      debugPrint(
          'SpellingWordsService: Got word ${word.word} (difficulty: ${word.difficulty}) for user $userId');
      return word;
    } catch (e) {
      debugPrint('SpellingWordsService: Error getting word: $e');
      return null;
    }
  }

  /// Mark a word as used for the current user
  static Future<void> markAsUsed(String wordId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint(
            'SpellingWordsService: No user logged in, cannot mark as used');
        return;
      }

      await _supabase.from(_historyTable).upsert(
        {
          'user_id': userId,
          'word_id': wordId,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,word_id',
      );
      debugPrint(
          'SpellingWordsService: Marked $wordId as used for user $userId');
    } catch (e) {
      debugPrint('SpellingWordsService: Error marking as used: $e');
    }
  }

  /// Get count of spelling words by difficulty
  static Future<Map<String, int>> getWordCounts() async {
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

      debugPrint('SpellingWordsService: Word counts: $counts');
      return counts;
    } catch (e) {
      debugPrint('SpellingWordsService: Error getting counts: $e');
      return {'easy': 0, 'medium': 0, 'hard': 0};
    }
  }
}
