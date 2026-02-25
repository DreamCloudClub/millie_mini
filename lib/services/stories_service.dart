import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/story_page.dart';
import 'supabase_service.dart';
import 'openai_service.dart';
import 'storage_service.dart';

/// Service for managing stories and their pages
class StoriesService {
  static final _supabase = Supabase.instance.client;
  static List<StoryPage>? _cachedPages;
  static Directory? _imageCacheDir;
  static Directory? _audioCacheDir;

  /// Initialize cache directories
  static Future<void> _ensureCacheDirs() async {
    if (_imageCacheDir != null && _audioCacheDir != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _imageCacheDir = Directory('${appDir.path}/story_images');
    _audioCacheDir = Directory('${appDir.path}/story_audio');

    if (!await _imageCacheDir!.exists()) {
      await _imageCacheDir!.create(recursive: true);
    }
    if (!await _audioCacheDir!.exists()) {
      await _audioCacheDir!.create(recursive: true);
    }
  }

  /// Load all story pages from database (cached after first load)
  static Future<void> _ensureLoaded() async {
    if (_cachedPages != null) return;

    try {
      final response = await SupabaseConfig.client
          .from('story_pages')
          .select()
          .order('story_id')
          .order('page_number');

      _cachedPages = (response as List)
          .map((json) => StoryPage.fromJson(json))
          .toList();

      debugPrint('StoriesService: Loaded ${_cachedPages!.length} story pages');
    } catch (e) {
      debugPrint('StoriesService: Error loading stories: $e');
      _cachedPages = [];
    }
  }

  /// Get list of available stories (for menu display)
  static Future<List<StorySummary>> getStoryList() async {
    await _ensureLoaded();

    if (_cachedPages == null || _cachedPages!.isEmpty) {
      return [];
    }

    // Group by story_id and get summary
    final Map<String, StorySummary> stories = {};
    for (final page in _cachedPages!) {
      if (!stories.containsKey(page.storyId)) {
        stories[page.storyId] = StorySummary(
          storyId: page.storyId,
          title: page.title,
          pageCount: _cachedPages!.where((p) => p.storyId == page.storyId).length,
        );
      }
    }

    return stories.values.toList();
  }

  /// Get all pages for a specific story, ordered by page number
  static Future<List<StoryPage>> getStoryPages(String storyId) async {
    await _ensureLoaded();

    if (_cachedPages == null) return [];

    return _cachedPages!
        .where((p) => p.storyId == storyId)
        .toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
  }

  /// Get local path for story image (downloads if not cached)
  static Future<String?> getLocalImagePath(StoryPage page) async {
    if (page.imageUrl == null || page.imageUrl!.isEmpty) return null;

    await _ensureCacheDirs();

    final filename = '${page.storyId}_${page.pageNumber}.png';
    final localFile = File('${_imageCacheDir!.path}/$filename');

    if (await localFile.exists()) {
      return localFile.path;
    }

    // Download from URL
    try {
      debugPrint('StoriesService: Downloading image for ${page.storyId} page ${page.pageNumber}');
      final response = await http.get(Uri.parse(page.imageUrl!));
      if (response.statusCode == 200) {
        await localFile.writeAsBytes(response.bodyBytes);
        debugPrint('StoriesService: Image cached at ${localFile.path}');
        return localFile.path;
      }
    } catch (e) {
      debugPrint('StoriesService: Error downloading image: $e');
    }

    return null;
  }

  /// Get audio path for story page (generates and caches if needed)
  static Future<String?> getAudioPath({
    required StoryPage page,
    required String voice,
  }) async {
    await _ensureCacheDirs();

    final filename = '${page.storyId}_${page.pageNumber}.mp3';
    final localFile = File('${_audioCacheDir!.path}/$filename');

    // Check local cache first
    if (await localFile.exists()) {
      debugPrint('StoriesService: Using cached audio for ${page.storyId} page ${page.pageNumber}');
      return localFile.path;
    }

    // Check if audio_url exists in database
    if (page.audioUrl != null && page.audioUrl!.isNotEmpty) {
      try {
        debugPrint('StoriesService: Downloading audio from database URL');
        final response = await http.get(Uri.parse(page.audioUrl!));
        if (response.statusCode == 200) {
          await localFile.writeAsBytes(response.bodyBytes);
          return localFile.path;
        }
      } catch (e) {
        debugPrint('StoriesService: Error downloading audio: $e');
      }
    }

    // Generate TTS and cache
    try {
      debugPrint('StoriesService: Generating TTS for ${page.storyId} page ${page.pageNumber}');
      final storageService = StorageService();
      await storageService.init();
      final openaiService = OpenAIService(storageService);

      final tempPath = await openaiService.textToSpeech(
        text: page.text,
        voice: voice,
        model: 'tts-1',
      );

      if (tempPath != null) {
        // Copy to cache
        final tempFile = File(tempPath);
        await tempFile.copy(localFile.path);

        // Upload to Supabase storage and update database
        await _uploadAndCacheAudio(page, localFile);

        return localFile.path;
      }
    } catch (e) {
      debugPrint('StoriesService: Error generating TTS: $e');
    }

    return null;
  }

  /// Upload audio to Supabase storage and update database
  static Future<void> _uploadAndCacheAudio(StoryPage page, File audioFile) async {
    try {
      final storagePath = '${page.storyId}/audio_${page.pageNumber}.mp3';

      // Upload to storage
      await _supabase.storage
          .from('stories')
          .upload(storagePath, audioFile, fileOptions: const FileOptions(upsert: true));

      // Get public URL
      final audioUrl = _supabase.storage
          .from('stories')
          .getPublicUrl(storagePath);

      // Update database
      await _supabase
          .from('story_pages')
          .update({'audio_url': audioUrl})
          .eq('id', page.id);

      // Update local cache
      if (_cachedPages != null) {
        final index = _cachedPages!.indexWhere((p) => p.id == page.id);
        if (index >= 0) {
          _cachedPages![index] = page.copyWith(audioUrl: audioUrl);
        }
      }

      debugPrint('StoriesService: Audio cached to Supabase: $audioUrl');
    } catch (e) {
      debugPrint('StoriesService: Error uploading audio to Supabase: $e');
    }
  }

  /// Sync all story images to local cache (call on app startup)
  static Future<void> syncImages() async {
    await _ensureLoaded();
    await _ensureCacheDirs();

    if (_cachedPages == null) return;

    for (final page in _cachedPages!) {
      if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
        await getLocalImagePath(page);
      }
    }

    debugPrint('StoriesService: Image sync complete');
  }

  /// Clear cache (for debugging/reset)
  static void clearCache() {
    _cachedPages = null;
  }
}
