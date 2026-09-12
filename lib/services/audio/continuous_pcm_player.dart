import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'assistant_audio_buffer.dart';

/// Playback state for the continuous PCM player
enum PlaybackState {
  stopped,
  starting,
  playing,
  paused,
  stopping,
  error,
}

/// Continuous PCM audio player using flutter_sound.
///
/// Key design:
/// - Opens audio output ONCE, keeps it open during conversation
/// - Consumes PCM from AssistantAudioBuffer via periodic callbacks
/// - Writes silence when buffer is temporarily empty (prevents glitches)
/// - Never recreates audio source for each chunk
class ContinuousPcmPlayer {
  // Audio format configuration (must match OpenAI Realtime output)
  static const int sampleRate = 24000;
  static const int numChannels = 1;
  static const int bitsPerSample = 16;
  static const Codec codec = Codec.pcm16;

  // Feed configuration
  static const int feedIntervalMs = 20; // Feed audio every 20ms
  static const int bytesPerFeed = (sampleRate * 2 * feedIntervalMs) ~/ 1000; // 960 bytes per 20ms

  // Buffer size for flutter_sound (must be power of 2)
  static const int playerBufferSize = 16384;  // Increased for smoother streaming

  // Player instance
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  // State
  PlaybackState _state = PlaybackState.stopped;
  PlaybackState get state => _state;

  // Buffer reference
  AssistantAudioBuffer? _buffer;

  // Feed timer
  Timer? _feedTimer;
  bool _isFeeding = false;
  bool _completionPending = false;  // Prevent multiple completion schedules

  // Statistics
  int _totalBytesPlayed = 0;
  int _silenceBytesFed = 0;
  int _feedCount = 0;
  DateTime? _playbackStartTime;

  // Callbacks
  void Function(PlaybackState state)? onStateChange;
  void Function()? onPlaybackComplete;
  void Function(String error)? onError;
  void Function(String event, Map<String, dynamic> data)? onDiagnostic;

  ContinuousPcmPlayer();

  /// Whether player is currently outputting audio
  bool get isPlaying => _state == PlaybackState.playing;

  /// Whether player is ready to receive audio
  bool get isActive =>
      _state == PlaybackState.playing || _state == PlaybackState.paused;

  /// Total bytes played in current session
  int get totalBytesPlayed => _totalBytesPlayed;

  /// Duration played in milliseconds
  int get playedDurationMs =>
      (_totalBytesPlayed * 1000) ~/ (sampleRate * 2);

  /// Initialize the player (call once at app startup)
  Future<void> initialize() async {
    try {
      await _player.openPlayer();
      debugPrint('🔊 [PCMPlayer] Initialized');
    } catch (e) {
      debugPrint('🔊 [PCMPlayer] ERROR initializing: $e');
      _setState(PlaybackState.error);
      onError?.call('Failed to initialize player: $e');
    }
  }

  /// Start continuous playback from the provided buffer
  Future<void> start(AssistantAudioBuffer buffer) async {
    if (_state == PlaybackState.playing) {
      debugPrint('🔊 [PCMPlayer] Already playing, ignoring start()');
      return;
    }

    _buffer = buffer;
    _totalBytesPlayed = 0;
    _silenceBytesFed = 0;
    _feedCount = 0;
    _playbackStartTime = DateTime.now();
    _completionPending = false;

    _setState(PlaybackState.starting);

    try {
      // Start the player with streaming configuration
      // interleaved: true means we use uint8ListSink for PCM16 data
      // bufferSize: must be power of 2, default 8192
      await _player.startPlayerFromStream(
        codec: codec,
        numChannels: numChannels,
        sampleRate: sampleRate,
        interleaved: true,
        bufferSize: playerBufferSize,
      );

      _setState(PlaybackState.playing);
      debugPrint('🔊 [PCMPlayer] Started continuous playback');

      _emitDiagnostic('playback_started', {
        'sampleRate': sampleRate,
        'channels': numChannels,
        'feedIntervalMs': feedIntervalMs,
        'bytesPerFeed': bytesPerFeed,
        'bufferSize': playerBufferSize,
      });

      // Start the feed timer
      _startFeedTimer();
    } catch (e) {
      debugPrint('🔊 [PCMPlayer] ERROR starting: $e');
      _setState(PlaybackState.error);
      onError?.call('Failed to start playback: $e');
    }
  }

  /// Start the periodic feed timer
  void _startFeedTimer() {
    _feedTimer?.cancel();
    _feedTimer = Timer.periodic(
      Duration(milliseconds: feedIntervalMs),
      (_) => _feedAudio(),
    );
  }

  /// Feed audio to the player
  void _feedAudio() {
    if (_state != PlaybackState.playing || _isFeeding) return;
    if (_buffer == null) return;

    _isFeeding = true;

    try {
      // Adaptive feeding: when buffer is getting full, feed more to catch up
      // This moves data from our buffer to flutter_sound's internal buffer faster
      final bufferedMs = _buffer!.bufferedMs;
      int feedBytes = bytesPerFeed;

      // Feed more aggressively as buffer fills up
      if (bufferedMs > 500) {
        feedBytes = bytesPerFeed * 2;
      }
      if (bufferedMs > 1000) {
        feedBytes = bytesPerFeed * 4;
      }
      if (bufferedMs > 2000) {
        feedBytes = bytesPerFeed * 8;  // Very aggressive when buffer is very full
      }

      // Read from buffer (fills with silence if empty)
      final pcmData = _buffer!.readFrames(feedBytes, fillWithSilence: true);

      if (pcmData.isNotEmpty) {
        // Feed to player using uint8ListSink (for interleaved PCM16)
        final sink = _player.uint8ListSink;
        if (sink != null) {
          sink.add(pcmData);
          _totalBytesPlayed += pcmData.length;
          _feedCount++;
        } else {
          debugPrint('🔊 [PCMPlayer] WARNING: uint8ListSink is null!');
        }

        // Track silence (silence is zeros, but we count based on buffer state)
        if (_buffer!.isEmpty && _buffer!.isResponseComplete) {
          _silenceBytesFed += pcmData.length;
        }
      }

      // Check if we should stop (buffer drained and response complete)
      if (_buffer!.isEmpty && _buffer!.isResponseComplete && !_completionPending) {
        _completionPending = true;

        // Calculate how much audio flutter_sound still needs to play
        final elapsed = _playbackStartTime != null
            ? DateTime.now().difference(_playbackStartTime!).inMilliseconds
            : 0;
        final audioSentMs = (_totalBytesPlayed * 1000) ~/ (sampleRate * 2);
        final remainingMs = audioSentMs - elapsed;

        if (remainingMs > 100) {
          // flutter_sound still has audio to play, wait for it
          debugPrint('🔊 [PCMPlayer] Buffer empty, waiting ${remainingMs}ms for flutter_sound to finish');
          Future.delayed(Duration(milliseconds: remainingMs + 200), () {
            _handlePlaybackComplete();
          });
        } else {
          // Audio should be done, small grace period for any stragglers
          Future.delayed(const Duration(milliseconds: 200), () {
            _handlePlaybackComplete();
          });
        }
      }
    } catch (e) {
      debugPrint('🔊 [PCMPlayer] ERROR feeding audio: $e');
    } finally {
      _isFeeding = false;
    }
  }

  /// Handle playback completion
  Future<void> _handlePlaybackComplete() async {
    if (_state != PlaybackState.playing) return;

    final duration = _playbackStartTime != null
        ? DateTime.now().difference(_playbackStartTime!).inMilliseconds
        : 0;

    debugPrint('🔊 [PCMPlayer] Playback complete '
        '(${playedDurationMs}ms audio, ${duration}ms elapsed, $_feedCount feeds)');

    _emitDiagnostic('playback_complete', {
      'totalBytesPlayed': _totalBytesPlayed,
      'silenceBytesFed': _silenceBytesFed,
      'feedCount': _feedCount,
      'durationMs': duration,
      'audioDurationMs': playedDurationMs,
    });

    // Stop the feed timer
    _feedTimer?.cancel();
    _feedTimer = null;

    // Stop the player so it can be restarted for next response
    try {
      await _player.stopPlayer();
    } catch (e) {
      debugPrint('🔊 [PCMPlayer] Error stopping player: $e');
    }

    _setState(PlaybackState.stopped);

    // Notify that this response is done
    onPlaybackComplete?.call();
  }

  /// Pause playback (keeps player open)
  Future<void> pause() async {
    if (_state != PlaybackState.playing) return;

    _feedTimer?.cancel();
    await _player.pausePlayer();
    _setState(PlaybackState.paused);
    debugPrint('🔊 [PCMPlayer] Paused');
  }

  /// Resume playback
  Future<void> resume() async {
    if (_state != PlaybackState.paused) return;

    await _player.resumePlayer();
    _setState(PlaybackState.playing);
    _startFeedTimer();
    debugPrint('🔊 [PCMPlayer] Resumed');
  }

  /// Stop playback completely
  Future<void> stop() async {
    if (_state == PlaybackState.stopped || _state == PlaybackState.stopping) {
      return;
    }

    _setState(PlaybackState.stopping);
    _feedTimer?.cancel();
    _feedTimer = null;
    _completionPending = false;

    try {
      await _player.stopPlayer();
    } catch (e) {
      debugPrint('🔊 [PCMPlayer] Error stopping: $e');
    }

    _setState(PlaybackState.stopped);
    debugPrint('🔊 [PCMPlayer] Stopped');

    _emitDiagnostic('playback_stopped', {
      'totalBytesPlayed': _totalBytesPlayed,
      'audioDurationMs': playedDurationMs,
    });
  }

  /// Clear any pending audio and reset for new response
  /// Does NOT stop the player - keeps it ready
  void clearForNewResponse() {
    // Buffer clearing is handled by the buffer itself
    // We just reset our counters
    _totalBytesPlayed = 0;
    _silenceBytesFed = 0;
    _feedCount = 0;
    _playbackStartTime = DateTime.now();
    _completionPending = false;

    debugPrint('🔊 [PCMPlayer] Cleared for new response');
  }

  /// Handle interruption - stop player so next response can start fresh
  Future<void> handleInterruption() async {
    if (_state != PlaybackState.playing && _state != PlaybackState.starting) return;

    _feedTimer?.cancel();
    _feedTimer = null;
    _completionPending = false;

    _emitDiagnostic('interruption_handled', {
      'bytesPlayedBeforeInterruption': _totalBytesPlayed,
    });

    debugPrint('🔊 [PCMPlayer] Handling interruption '
        '(played ${playedDurationMs}ms before interrupt)');

    // Stop player so start() can be called for next response
    try {
      await _player.stopPlayer();
    } catch (e) {
      debugPrint('🔊 [PCMPlayer] Error stopping on interruption: $e');
    }
    _setState(PlaybackState.stopped);
  }

  /// Resume after interruption with new buffer content
  void resumeAfterInterruption() {
    if (_state == PlaybackState.playing) {
      _startFeedTimer();
      debugPrint('🔊 [PCMPlayer] Resumed after interruption');
    }
  }

  void _setState(PlaybackState newState) {
    if (_state == newState) return;

    final oldState = _state;
    _state = newState;

    debugPrint('🔊 [PCMPlayer] State: ${oldState.name} → ${newState.name}');
    onStateChange?.call(newState);
  }

  void _emitDiagnostic(String event, Map<String, dynamic> data) {
    onDiagnostic?.call(event, {
      ...data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get diagnostic info
  Map<String, dynamic> getDiagnostics() {
    return {
      'state': _state.name,
      'totalBytesPlayed': _totalBytesPlayed,
      'silenceBytesFed': _silenceBytesFed,
      'feedCount': _feedCount,
      'playedDurationMs': playedDurationMs,
      'isPlaying': isPlaying,
      'isActive': isActive,
    };
  }

  /// Dispose of all resources (call on app shutdown)
  Future<void> dispose() async {
    await stop();
    await _player.closePlayer();
    debugPrint('🔊 [PCMPlayer] Disposed');
  }
}
