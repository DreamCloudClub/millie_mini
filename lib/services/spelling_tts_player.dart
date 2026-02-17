import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'openai_service.dart';

/// Specialized TTS player for spelling words letter-by-letter.
/// Uses per-letter TTS calls with caching to ensure no letters are skipped.
class SpellingTtsPlayer {
  final OpenAIService _openAIService;
  final AudioPlayer _player = AudioPlayer();

  // In-memory cache index (voice+text -> path). Disk is source of truth.
  final Map<String, String> _cacheIndex = {};

  // Path to silence file (generated on first use)
  String? _silence250msPath;

  SpellingTtsPlayer(this._openAIService);

  /// Initialize the player (ensures silence file exists)
  Future<void> init() async {
    _silence250msPath ??= await _ensureSilenceFileOnDisk();
  }

  /// Play incorrect spelling feedback with reliable letter-by-letter TTS.
  ///
  /// This method:
  /// 1. Prefetches all letter audio in parallel
  /// 2. Plays the intro sentence
  /// 3. Plays each letter sequentially with pauses between
  Future<void> playIncorrectSpelling({
    required String word,
    required String voice,
    required String model,
  }) async {
    await init();

    final lowerWord = word.toLowerCase();
    final letters = word.toUpperCase().split('');

    debugPrint('SpellingTtsPlayer: Playing spelling for "$word" (${letters.length} letters)');

    // 1) Prefetch all letter audio in parallel while we prepare
    final prefetchFutures = <Future<void>>[];
    for (final letter in letters) {
      prefetchFutures.add(_prefetchLetter(
        letter: letter,
        voice: voice,
        model: model,
      ));
    }

    // 2) Play intro sentence first
    final introText = "Not quite. The word is $lowerWord.";
    final introPath = await _getOrCreateAudioPath(
      text: introText,
      voice: voice,
      model: model,
    );

    if (introPath != null) {
      await _playFileAndWait(introPath);
    }

    // 3) Wait for all letter prefetches to complete
    await Future.wait(prefetchFutures);

    // 4) Play each letter sequentially with silence between
    for (int i = 0; i < letters.length; i++) {
      final letter = letters[i];

      final letterPath = await _getOrCreateAudioPath(
        text: letter,
        voice: voice,
        model: model,
      );

      if (letterPath != null) {
        debugPrint('SpellingTtsPlayer: Playing letter "$letter"');
        await _playFileAndWait(letterPath);
      }

      // Insert silence after each letter except the last
      if (i < letters.length - 1 && _silence250msPath != null) {
        await _playFileAndWait(_silence250msPath!);
      }
    }

    debugPrint('SpellingTtsPlayer: Finished spelling "$word"');
  }

  /// Play a file and wait for completion
  Future<void> _playFileAndWait(String path) async {
    final completer = Completer<void>();

    final sub = _player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await _player.play(DeviceFileSource(path));
      await completer.future.timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('SpellingTtsPlayer: Error playing file: $e');
      if (!completer.isCompleted) {
        completer.complete();
      }
    } finally {
      await sub.cancel();
    }
  }

  /// Prefetch a letter's audio (for parallel downloading)
  Future<void> _prefetchLetter({
    required String letter,
    required String voice,
    required String model,
  }) async {
    await _getOrCreateAudioPath(
      text: letter,
      voice: voice,
      model: model,
    );
  }

  /// Get cached audio path or create new one via TTS
  Future<String?> _getOrCreateAudioPath({
    required String text,
    required String voice,
    required String model,
  }) async {
    final key = _cacheKey(text: text, voice: voice, model: model);

    // Check in-memory index first
    final indexed = _cacheIndex[key];
    if (indexed != null && await File(indexed).exists()) {
      return indexed;
    }

    // Check disk cache
    final dir = await getTemporaryDirectory();
    final fileName = 'millie_spell_${_safeHash(key)}.mp3';
    final path = '${dir.path}/$fileName';
    final file = File(path);

    if (await file.exists()) {
      _cacheIndex[key] = path;
      return path;
    }

    // Generate new audio via OpenAI TTS
    debugPrint('SpellingTtsPlayer: Generating TTS for "$text"');
    final audioPath = await _openAIService.textToSpeech(
      text: text,
      voice: voice,
      model: model,
    );

    if (audioPath != null) {
      // Copy to our cache location for consistent naming
      final sourceFile = File(audioPath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(path);
        _cacheIndex[key] = path;
        return path;
      }
    }

    return audioPath; // Fall back to original path if copy failed
  }

  /// Generate cache key from parameters
  String _cacheKey({
    required String text,
    required String voice,
    required String model,
  }) {
    return 'v=$voice|m=$model|t=${text.trim()}';
  }

  /// Create a filename-safe hash of the cache key
  String _safeHash(String s) {
    final bytes = utf8.encode(s);
    return base64Url.encode(bytes).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  /// Create a 250ms silence MP3 file on disk
  /// Uses a minimal valid MP3 with silence
  Future<String> _ensureSilenceFileOnDisk() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/millie_silence_250ms.mp3';
    final file = File(path);

    if (await file.exists()) {
      return path;
    }

    // Minimal valid MP3 frame with silence (~250ms)
    // This is a valid MP3 file with silent frames
    final silenceBytes = _generateSilenceMp3Bytes();
    await file.writeAsBytes(silenceBytes, flush: true);
    debugPrint('SpellingTtsPlayer: Created silence file at $path');
    return path;
  }

  /// Generate minimal MP3 bytes for ~250ms of silence
  List<int> _generateSilenceMp3Bytes() {
    // A minimal valid MP3 file with silence
    // MP3 frame header for 128kbps, 44100Hz, stereo, ~26ms per frame
    // We need about 10 frames for ~250ms

    final bytes = <int>[];

    // MP3 frame: sync word (0xFF 0xFB), layer 3, 128kbps, 44100Hz
    // Frame header: FF FB 90 00 (simplified valid header)
    // Each frame is 417 bytes at 128kbps/44100Hz

    const frameHeader = [0xFF, 0xFB, 0x90, 0x00];
    const frameSize = 417; // bytes per frame at 128kbps
    const numFrames = 10; // ~260ms of audio

    for (int i = 0; i < numFrames; i++) {
      bytes.addAll(frameHeader);
      // Fill rest of frame with zeros (silence)
      for (int j = 0; j < frameSize - frameHeader.length; j++) {
        bytes.add(0x00);
      }
    }

    return bytes;
  }

  /// Stop any currently playing audio
  Future<void> stop() async {
    await _player.stop();
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _player.dispose();
  }

  /// Clear the audio cache
  Future<void> clearCache() async {
    _cacheIndex.clear();

    final dir = await getTemporaryDirectory();
    final cacheDir = Directory(dir.path);

    await for (final entity in cacheDir.list()) {
      if (entity is File && entity.path.contains('millie_spell_')) {
        try {
          await entity.delete();
        } catch (e) {
          debugPrint('SpellingTtsPlayer: Error deleting cache file: $e');
        }
      }
    }
  }
}
