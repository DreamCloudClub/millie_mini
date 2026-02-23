import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'openai_service.dart';
import 'storage_service.dart';

/// A food problem for the foods quiz/lessons
class FoodProblem {
  final String id;
  final String answer;
  final List<String> aliases;
  final String hint;
  final String imageUrl;
  final String? narrationAudioUrl;

  const FoodProblem({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.hint,
    required this.imageUrl,
    this.narrationAudioUrl,
  });
}

/// Service for generating food quiz/lesson content
/// Uses per-user tracking via user_food_history table
class FoodsService {
  static final _supabase = Supabase.instance.client;
  static const String _historyTable = 'user_food_history';
  static List<_FoodData>? _cachedFoods;

  /// Load foods from database (cached after first load)
  static Future<void> _ensureLoaded() async {
    if (_cachedFoods != null) return;

    try {
      final response = await SupabaseConfig.client
          .from('foods')
          .select();

      _cachedFoods = (response as List).map((json) {
        final name = json['name'] as String;
        final narration = json['narration_text'] as String;
        final imageUrl = json['image_url'] as String?;
        final narrationAudioUrl = json['narration_audio_url'] as String?;
        final customQuizHint = json['quiz_hint'] as String?;

        // Quiz hint: use custom hint if available, otherwise fall back to short description
        final quizHint = (customQuizHint != null && customQuizHint.isNotEmpty)
            ? '$customQuizHint What is it called?'
            : '${_getShortDescription(narration)} What is it called?';

        // Lesson hint: full narration + "Can you say [food]?"
        final lessonHint = '$narration Can you say $name?';

        return _FoodData(
          id: json['id'] as String,
          answer: name,
          aliases: [
            name.toLowerCase(),
            'a ${name.toLowerCase()}',
            'the ${name.toLowerCase()}',
            // Handle plurals
            if (name.toLowerCase().endsWith('s'))
              name.toLowerCase().substring(0, name.length - 1),
          ],
          quizHint: quizHint,
          lessonHint: lessonHint,
          imageUrl: imageUrl ?? '',
          narrationAudioUrl: narrationAudioUrl,
        );
      }).toList();
    } catch (e) {
      debugPrint('FoodsService: Error loading foods: $e');
      _cachedFoods = [];
    }
  }

  /// Generate a random food quiz problem (prioritizes unseen, then oldest seen)
  static Future<FoodProblem?> generate({Set<String>? excludeIds}) async {
    try {
      await _ensureLoaded();

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('FoodsService: No user logged in');
        return null;
      }

      if (_cachedFoods == null || _cachedFoods!.isEmpty) {
        return null;
      }

      // Get user's food history
      final historyResponse = await _supabase
          .from(_historyTable)
          .select('food_id, last_used_at')
          .eq('user_id', userId);

      final historyMap = <String, DateTime>{};
      for (final row in historyResponse) {
        historyMap[row['food_id'] as String] =
            DateTime.parse(row['last_used_at'] as String);
      }

      // Filter out excluded IDs (already asked this session)
      var available = _cachedFoods!
          .where((f) => excludeIds == null || !excludeIds.contains(f.id))
          .toList();

      if (available.isEmpty) {
        return null;
      }

      // Sort: foods not in history first (never seen), then by oldest seen
      available.sort((a, b) {
        final aUsed = historyMap[a.id];
        final bUsed = historyMap[b.id];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1;
        if (bUsed == null) return 1;
        return aUsed.compareTo(bUsed);
      });

      final food = available.first;

      return FoodProblem(
        id: food.id,
        answer: food.answer,
        aliases: food.aliases,
        hint: food.quizHint,
        imageUrl: food.imageUrl,
        narrationAudioUrl: food.narrationAudioUrl,
      );
    } catch (e) {
      debugPrint('FoodsService: Error generating food: $e');
      return null;
    }
  }

  /// Generate a random food lesson (prioritizes unseen, then oldest seen)
  static Future<FoodProblem?> generateLesson({Set<String>? excludeIds}) async {
    try {
      await _ensureLoaded();

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('FoodsService: No user logged in');
        return null;
      }

      if (_cachedFoods == null || _cachedFoods!.isEmpty) {
        return null;
      }

      // Get user's food history
      final historyResponse = await _supabase
          .from(_historyTable)
          .select('food_id, last_used_at')
          .eq('user_id', userId);

      final historyMap = <String, DateTime>{};
      for (final row in historyResponse) {
        historyMap[row['food_id'] as String] =
            DateTime.parse(row['last_used_at'] as String);
      }

      // Filter out excluded IDs (already asked this session)
      var available = _cachedFoods!
          .where((f) => excludeIds == null || !excludeIds.contains(f.id))
          .toList();

      if (available.isEmpty) {
        return null;
      }

      // Sort: foods not in history first (never seen), then by oldest seen
      available.sort((a, b) {
        final aUsed = historyMap[a.id];
        final bUsed = historyMap[b.id];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1;
        if (bUsed == null) return 1;
        return aUsed.compareTo(bUsed);
      });

      final food = available.first;

      return FoodProblem(
        id: food.id,
        answer: food.answer,
        aliases: food.aliases,
        hint: food.lessonHint,
        imageUrl: food.imageUrl,
        narrationAudioUrl: food.narrationAudioUrl,
      );
    } catch (e) {
      debugPrint('FoodsService: Error generating food lesson: $e');
      return null;
    }
  }

  /// Mark a food as used for the current user
  static Future<void> markAsUsed(String foodId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('FoodsService: No user logged in, cannot mark as used');
        return;
      }

      await _supabase.from(_historyTable).upsert(
        {
          'user_id': userId,
          'food_id': foodId,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,food_id',
      );
      debugPrint('FoodsService: Marked $foodId as used for user $userId');
    } catch (e) {
      debugPrint('FoodsService: Error marking as used: $e');
    }
  }

  /// Get image URL for a food by ID
  static Future<String?> getImageUrl(String foodId) async {
    await _ensureLoaded();
    for (final food in _cachedFoods ?? []) {
      if (food.id == foodId) {
        return food.imageUrl;
      }
    }
    return null;
  }

  /// Get total number of foods available
  static Future<int> get totalFoods async {
    await _ensureLoaded();
    return _cachedFoods?.length ?? 0;
  }

  /// Get audio file path for a food's narration (cached or generate new)
  static Future<String?> getAudioPath({
    required String foodId,
    required String text,
    required String voice,
  }) async {
    await _ensureLoaded();

    // Find the food
    final food = _cachedFoods?.firstWhere(
      (f) => f.id == foodId,
      orElse: () => throw Exception('Food not found'),
    );

    if (food == null) return null;

    // If cached audio exists, download and return local path
    if (food.narrationAudioUrl != null && food.narrationAudioUrl!.isNotEmpty) {
      debugPrint('FoodsService: Using cached audio for ${food.answer}');
      return await _downloadToLocal(food.narrationAudioUrl!, foodId);
    }

    // Generate new audio via OpenAI TTS
    debugPrint('FoodsService: Generating new audio for ${food.answer}');
    final storageService = StorageService();
    await storageService.init();
    final openAI = OpenAIService(storageService);
    final localPath = await openAI.textToSpeech(
      text: text,
      voice: voice,
      model: 'tts-1',
    );

    if (localPath == null) return null;

    // Upload to Supabase storage
    final audioUrl = await _uploadToStorage(localPath, foodId);
    if (audioUrl != null) {
      // Update database with cached URL
      await _updateAudioUrl(foodId, audioUrl);
      // Refresh cache
      _cachedFoods = null;
    }

    return localPath;
  }

  /// Download audio from URL to local temp file
  static Future<String?> _downloadToLocal(String url, String foodId) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/food_$foodId.mp3';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('FoodsService: Downloaded audio to $filePath');
        return filePath;
      }
    } catch (e) {
      debugPrint('FoodsService: Error downloading audio: $e');
    }
    return null;
  }

  /// Upload audio file to Supabase storage
  static Future<String?> _uploadToStorage(String localPath, String foodId) async {
    try {
      final file = File(localPath);
      final bytes = await file.readAsBytes();
      final fileName = 'narrations/$foodId.mp3';

      await SupabaseConfig.client.storage
          .from('food')
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));

      final url = SupabaseConfig.client.storage
          .from('food')
          .getPublicUrl(fileName);

      debugPrint('FoodsService: Uploaded audio to $url');
      return url;
    } catch (e) {
      debugPrint('FoodsService: Error uploading audio: $e');
      return null;
    }
  }

  /// Update food row with cached audio URL
  static Future<void> _updateAudioUrl(String foodId, String audioUrl) async {
    try {
      await SupabaseConfig.client
          .from('foods')
          .update({'narration_audio_url': audioUrl})
          .eq('id', foodId);
      debugPrint('FoodsService: Updated audio URL in database');
    } catch (e) {
      debugPrint('FoodsService: Error updating audio URL: $e');
    }
  }

  static String _getShortDescription(String narration) {
    // Take first 2 sentences
    final sentences = narration.split(RegExp(r'[.!?]+\s*'));
    if (sentences.length <= 2) return narration;

    final short = sentences.take(2).join('. ');
    return short.isNotEmpty ? '$short.' : narration;
  }
}

/// Internal food data class
class _FoodData {
  final String id;
  final String answer;
  final List<String> aliases;
  final String quizHint;
  final String lessonHint;
  final String imageUrl;
  final String? narrationAudioUrl;

  const _FoodData({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.quizHint,
    required this.lessonHint,
    required this.imageUrl,
    this.narrationAudioUrl,
  });
}
