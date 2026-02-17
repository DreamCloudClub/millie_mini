import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'openai_service.dart';
import 'storage_service.dart';

/// An animal problem for the animals quiz/lessons
class AnimalProblem {
  final String id;
  final String answer;
  final List<String> aliases;
  final String hint;
  final String imageUrl;
  final String? narrationAudioUrl;

  const AnimalProblem({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.hint,
    required this.imageUrl,
    this.narrationAudioUrl,
  });
}

/// Service for generating animal quiz/lesson content
/// Uses per-user tracking via user_animal_history table
class AnimalsService {
  static final _supabase = Supabase.instance.client;
  static const String _historyTable = 'user_animal_history';
  static List<_AnimalData>? _cachedAnimals;

  /// Load animals from database (cached after first load)
  static Future<void> _ensureLoaded() async {
    if (_cachedAnimals != null) return;

    try {
      final response = await SupabaseConfig.client
          .from('animals')
          .select();

      _cachedAnimals = (response as List).map((json) {
        final name = json['name'] as String;
        final narration = json['narration_text'] as String;
        final imageUrl = json['image_url'] as String?;
        final narrationAudioUrl = json['narration_audio_url'] as String?;
        final customQuizHint = json['quiz_hint'] as String?;

        // Quiz hint: use custom hint if available, otherwise fall back to short description
        final quizHint = (customQuizHint != null && customQuizHint.isNotEmpty)
            ? '$customQuizHint What is it called?'
            : '${_getShortDescription(narration)} What is it called?';

        // Lesson hint: full narration + "Can you say [animal]?"
        final lessonHint = '$narration Can you say $name?';

        return _AnimalData(
          id: json['id'] as String,
          answer: name,
          aliases: [
            name.toLowerCase(),
            'a ${name.toLowerCase()}',
            'the ${name.toLowerCase()}',
          ],
          quizHint: quizHint,
          lessonHint: lessonHint,
          imageUrl: imageUrl ?? '',
          narrationAudioUrl: narrationAudioUrl,
        );
      }).toList();
    } catch (e) {
      debugPrint('AnimalsService: Error loading animals: $e');
      _cachedAnimals = [];
    }
  }

  /// Generate a random animal quiz problem (prioritizes unseen, then oldest seen)
  static Future<AnimalProblem?> generate({Set<String>? excludeIds}) async {
    try {
      await _ensureLoaded();

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('AnimalsService: No user logged in');
        return null;
      }

      if (_cachedAnimals == null || _cachedAnimals!.isEmpty) {
        return null;
      }

      // Get user's animal history
      final historyResponse = await _supabase
          .from(_historyTable)
          .select('animal_id, last_used_at')
          .eq('user_id', userId);

      final historyMap = <String, DateTime>{};
      for (final row in historyResponse) {
        historyMap[row['animal_id'] as String] =
            DateTime.parse(row['last_used_at'] as String);
      }

      // Filter out excluded IDs (already asked this session)
      var available = _cachedAnimals!
          .where((a) => excludeIds == null || !excludeIds.contains(a.id))
          .toList();

      if (available.isEmpty) {
        return null;
      }

      // Sort: animals not in history first (never seen), then by oldest seen
      available.sort((a, b) {
        final aUsed = historyMap[a.id];
        final bUsed = historyMap[b.id];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1;
        if (bUsed == null) return 1;
        return aUsed.compareTo(bUsed);
      });

      final animal = available.first;

      return AnimalProblem(
        id: animal.id,
        answer: animal.answer,
        aliases: animal.aliases,
        hint: animal.quizHint,
        imageUrl: animal.imageUrl,
        narrationAudioUrl: animal.narrationAudioUrl,
      );
    } catch (e) {
      debugPrint('AnimalsService: Error generating animal: $e');
      return null;
    }
  }

  /// Generate a random animal lesson (prioritizes unseen, then oldest seen)
  static Future<AnimalProblem?> generateLesson({Set<String>? excludeIds}) async {
    try {
      await _ensureLoaded();

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('AnimalsService: No user logged in');
        return null;
      }

      if (_cachedAnimals == null || _cachedAnimals!.isEmpty) {
        return null;
      }

      // Get user's animal history
      final historyResponse = await _supabase
          .from(_historyTable)
          .select('animal_id, last_used_at')
          .eq('user_id', userId);

      final historyMap = <String, DateTime>{};
      for (final row in historyResponse) {
        historyMap[row['animal_id'] as String] =
            DateTime.parse(row['last_used_at'] as String);
      }

      // Filter out excluded IDs (already asked this session)
      var available = _cachedAnimals!
          .where((a) => excludeIds == null || !excludeIds.contains(a.id))
          .toList();

      if (available.isEmpty) {
        return null;
      }

      // Sort: animals not in history first (never seen), then by oldest seen
      available.sort((a, b) {
        final aUsed = historyMap[a.id];
        final bUsed = historyMap[b.id];

        if (aUsed == null && bUsed == null) return 0;
        if (aUsed == null) return -1;
        if (bUsed == null) return 1;
        return aUsed.compareTo(bUsed);
      });

      final animal = available.first;

      return AnimalProblem(
        id: animal.id,
        answer: animal.answer,
        aliases: animal.aliases,
        hint: animal.lessonHint,
        imageUrl: animal.imageUrl,
        narrationAudioUrl: animal.narrationAudioUrl,
      );
    } catch (e) {
      debugPrint('AnimalsService: Error generating animal lesson: $e');
      return null;
    }
  }

  /// Mark an animal as used for the current user
  static Future<void> markAsUsed(String animalId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('AnimalsService: No user logged in, cannot mark as used');
        return;
      }

      await _supabase.from(_historyTable).upsert(
        {
          'user_id': userId,
          'animal_id': animalId,
          'last_used_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,animal_id',
      );
      debugPrint('AnimalsService: Marked $animalId as used for user $userId');
    } catch (e) {
      debugPrint('AnimalsService: Error marking as used: $e');
    }
  }

  /// Get image URL for an animal by ID
  static Future<String?> getImageUrl(String animalId) async {
    await _ensureLoaded();
    for (final animal in _cachedAnimals ?? []) {
      if (animal.id == animalId) {
        return animal.imageUrl;
      }
    }
    return null;
  }

  /// Get total number of animals available
  static Future<int> get totalAnimals async {
    await _ensureLoaded();
    return _cachedAnimals?.length ?? 0;
  }

  /// Get audio file path for an animal's narration (cached or generate new)
  static Future<String?> getAudioPath({
    required String animalId,
    required String text,
    required String voice,
  }) async {
    await _ensureLoaded();

    // Find the animal
    final animal = _cachedAnimals?.firstWhere(
      (a) => a.id == animalId,
      orElse: () => throw Exception('Animal not found'),
    );

    if (animal == null) return null;

    // If cached audio exists, download and return local path
    if (animal.narrationAudioUrl != null && animal.narrationAudioUrl!.isNotEmpty) {
      debugPrint('AnimalsService: Using cached audio for ${animal.answer}');
      return await _downloadToLocal(animal.narrationAudioUrl!, animalId);
    }

    // Generate new audio via OpenAI TTS
    debugPrint('AnimalsService: Generating new audio for ${animal.answer}');
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
    final audioUrl = await _uploadToStorage(localPath, animalId);
    if (audioUrl != null) {
      // Update database with cached URL
      await _updateAudioUrl(animalId, audioUrl);
      // Refresh cache
      _cachedAnimals = null;
    }

    return localPath;
  }

  /// Download audio from URL to local temp file
  static Future<String?> _downloadToLocal(String url, String animalId) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/animal_$animalId.mp3';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('AnimalsService: Downloaded audio to $filePath');
        return filePath;
      }
    } catch (e) {
      debugPrint('AnimalsService: Error downloading audio: $e');
    }
    return null;
  }

  /// Upload audio file to Supabase storage
  static Future<String?> _uploadToStorage(String localPath, String animalId) async {
    try {
      final file = File(localPath);
      final bytes = await file.readAsBytes();
      final fileName = 'narrations/$animalId.mp3';

      await SupabaseConfig.client.storage
          .from('animals')
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));

      final url = SupabaseConfig.client.storage
          .from('animals')
          .getPublicUrl(fileName);

      debugPrint('AnimalsService: Uploaded audio to $url');
      return url;
    } catch (e) {
      debugPrint('AnimalsService: Error uploading audio: $e');
      return null;
    }
  }

  /// Update animal row with cached audio URL
  static Future<void> _updateAudioUrl(String animalId, String audioUrl) async {
    try {
      await SupabaseConfig.client
          .from('animals')
          .update({'narration_audio_url': audioUrl})
          .eq('id', animalId);
      debugPrint('AnimalsService: Updated audio URL in database');
    } catch (e) {
      debugPrint('AnimalsService: Error updating audio URL: $e');
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

/// Internal animal data class
class _AnimalData {
  final String id;
  final String answer;
  final List<String> aliases;
  final String quizHint;
  final String lessonHint;
  final String imageUrl;
  final String? narrationAudioUrl;

  const _AnimalData({
    required this.id,
    required this.answer,
    required this.aliases,
    required this.quizHint,
    required this.lessonHint,
    required this.imageUrl,
    this.narrationAudioUrl,
  });
}
