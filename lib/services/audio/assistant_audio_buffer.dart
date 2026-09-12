import 'package:flutter/foundation.dart';

/// FIFO buffer for PCM16 audio with response tracking and jitter buffering.
///
/// Audio format: PCM16 mono at 24kHz
/// - 24000 samples/second × 2 bytes/sample = 48000 bytes/second
/// - 100ms = 4800 bytes
/// - 300ms = 14400 bytes
/// - 500ms = 24000 bytes
class AssistantAudioBuffer {
  // Buffer configuration
  static const int sampleRate = 24000;
  static const int bytesPerSample = 2; // PCM16
  static const int bytesPerSecond = sampleRate * bytesPerSample; // 48000

  // Jitter buffer thresholds
  static const int startThresholdMs = 100;  // Start playing quickly to drain buffer
  static const int idealBufferMs = 300;
  static const int maxBufferMs = 3000;  // Allow larger bursts from OpenAI

  static const int startThresholdBytes = (startThresholdMs * bytesPerSecond) ~/ 1000; // 4800
  static const int idealBufferBytes = (idealBufferMs * bytesPerSecond) ~/ 1000; // 14400
  static const int maxBufferBytes = (maxBufferMs * bytesPerSecond) ~/ 1000; // 144000

  // Ring buffer implementation
  late Uint8List _buffer;
  int _writePos = 0;
  int _readPos = 0;
  int _bufferedBytes = 0;

  // Response tracking
  String? _currentResponseId;
  int _deltaCount = 0;
  int _totalBytesReceived = 0;
  bool _responseComplete = false;

  // Odd byte handling (PCM16 needs 2-byte alignment)
  int? _pendingOddByte;

  // Statistics
  int _underrunCount = 0;
  int _overrunCount = 0;
  int _silenceBytesInserted = 0;

  // Callbacks
  void Function(int bufferedMs)? onBufferLevelChange;
  void Function()? onUnderrun;
  void Function()? onReadyToPlay;

  bool _readyToPlayFired = false;

  AssistantAudioBuffer({int capacityMs = 20000}) {
    final capacityBytes = (capacityMs * bytesPerSecond) ~/ 1000;
    _buffer = Uint8List(capacityBytes);
    debugPrint('🎵 [AudioBuffer] Created with ${capacityBytes} byte capacity (${capacityMs}ms)');
  }

  /// Current buffered duration in milliseconds
  int get bufferedMs => (_bufferedBytes * 1000) ~/ bytesPerSecond;

  /// Current buffered bytes
  int get bufferedBytes => _bufferedBytes;

  /// Whether buffer has enough data to start playback
  bool get isReadyToPlay => _bufferedBytes >= startThresholdBytes;

  /// Whether buffer is empty
  bool get isEmpty => _bufferedBytes == 0;

  /// Whether response audio is complete (no more expected)
  bool get isResponseComplete => _responseComplete;

  /// Current response ID being buffered
  String? get currentResponseId => _currentResponseId;

  /// Statistics
  int get underrunCount => _underrunCount;
  int get overrunCount => _overrunCount;
  int get silenceBytesInserted => _silenceBytesInserted;
  int get deltaCount => _deltaCount;
  int get totalBytesReceived => _totalBytesReceived;

  /// Mark the start of a new response
  void markResponseStart(String responseId) {
    // If same response ID and we have data, don't clear - prevents restart glitch
    if (_currentResponseId == responseId && _bufferedBytes > 0) {
      debugPrint('🎵 [AudioBuffer] Same response ID with data, not clearing: $responseId');
      return;
    }

    // If we have data from a different response, clear it
    if (_bufferedBytes > 0 && _currentResponseId != responseId) {
      debugPrint('🎵 [AudioBuffer] Clearing ${_bufferedBytes} bytes from previous response');
      _writePos = 0;
      _readPos = 0;
      _bufferedBytes = 0;
    }

    _currentResponseId = responseId;
    _deltaCount = 0;
    _totalBytesReceived = 0;
    _responseComplete = false;
    _readyToPlayFired = false;
    _pendingOddByte = null;

    debugPrint('🎵 [AudioBuffer] Response started: $responseId');
  }

  /// Mark the end of a response (no more audio expected)
  void markResponseEnd(String responseId) {
    if (_currentResponseId != responseId) {
      debugPrint('🎵 [AudioBuffer] Ignoring response end for stale ID: $responseId');
      return;
    }

    _responseComplete = true;
    debugPrint('🎵 [AudioBuffer] Response ended: $responseId '
        '(${_deltaCount} deltas, ${_totalBytesReceived} bytes, ${bufferedMs}ms buffered)');
  }

  /// Append a PCM16 chunk to the buffer
  /// Returns false if chunk was rejected (wrong response ID or buffer full)
  bool appendChunk(Uint8List pcmBytes, {String? responseId}) {
    // Validate response ID if provided
    if (responseId != null && _currentResponseId != null && responseId != _currentResponseId) {
      debugPrint('🎵 [AudioBuffer] Rejecting chunk for stale response: $responseId (current: $_currentResponseId)');
      return false;
    }

    // Handle odd byte from previous chunk (PCM16 needs 2-byte alignment)
    Uint8List alignedBytes;
    if (_pendingOddByte != null) {
      alignedBytes = Uint8List(pcmBytes.length + 1);
      alignedBytes[0] = _pendingOddByte!;
      alignedBytes.setRange(1, pcmBytes.length + 1, pcmBytes);
      _pendingOddByte = null;
    } else {
      alignedBytes = pcmBytes;
    }

    // Check for odd length and hold last byte
    if (alignedBytes.length % 2 != 0) {
      _pendingOddByte = alignedBytes.last;
      alignedBytes = alignedBytes.sublist(0, alignedBytes.length - 1);
    }

    if (alignedBytes.isEmpty) {
      return true;
    }

    // Check for buffer overflow
    if (_bufferedBytes + alignedBytes.length > _buffer.length) {
      _overrunCount++;
      debugPrint('🎵 [AudioBuffer] OVERRUN: dropping ${alignedBytes.length} bytes '
          '(buffer: $_bufferedBytes/${_buffer.length})');
      return false;
    }

    // Write to ring buffer
    final bytesToEnd = _buffer.length - _writePos;
    if (alignedBytes.length <= bytesToEnd) {
      _buffer.setRange(_writePos, _writePos + alignedBytes.length, alignedBytes);
    } else {
      // Wrap around
      _buffer.setRange(_writePos, _buffer.length, alignedBytes.sublist(0, bytesToEnd));
      _buffer.setRange(0, alignedBytes.length - bytesToEnd, alignedBytes.sublist(bytesToEnd));
    }

    _writePos = (_writePos + alignedBytes.length) % _buffer.length;
    _bufferedBytes += alignedBytes.length;
    _deltaCount++;
    _totalBytesReceived += alignedBytes.length;

    // Check if ready to play
    if (!_readyToPlayFired && isReadyToPlay) {
      _readyToPlayFired = true;
      onReadyToPlay?.call();
      debugPrint('🎵 [AudioBuffer] Ready to play (${bufferedMs}ms buffered)');
    }

    onBufferLevelChange?.call(bufferedMs);

    return true;
  }

  /// Read frames from the buffer
  /// If fillWithSilence is true, returns silence for missing bytes
  /// Returns the actual PCM data (may be shorter than requested if not filling)
  Uint8List readFrames(int byteCount, {bool fillWithSilence = true}) {
    if (byteCount <= 0) return Uint8List(0);

    // Ensure even byte count for PCM16
    byteCount = (byteCount ~/ 2) * 2;

    final availableBytes = _bufferedBytes.clamp(0, byteCount);
    final result = Uint8List(fillWithSilence ? byteCount : availableBytes);

    if (availableBytes > 0) {
      // Read from ring buffer
      final bytesToEnd = _buffer.length - _readPos;
      if (availableBytes <= bytesToEnd) {
        result.setRange(0, availableBytes, _buffer.sublist(_readPos, _readPos + availableBytes));
      } else {
        // Wrap around
        result.setRange(0, bytesToEnd, _buffer.sublist(_readPos, _buffer.length));
        result.setRange(bytesToEnd, availableBytes, _buffer.sublist(0, availableBytes - bytesToEnd));
      }

      _readPos = (_readPos + availableBytes) % _buffer.length;
      _bufferedBytes -= availableBytes;
    }

    // Fill remaining with silence if needed
    if (fillWithSilence && availableBytes < byteCount) {
      final silenceBytes = byteCount - availableBytes;
      // result is already zero-initialized (silence for PCM16)
      _silenceBytesInserted += silenceBytes;

      if (availableBytes == 0 && _bufferedBytes == 0) {
        _underrunCount++;
        onUnderrun?.call();
      }
    }

    if (_bufferedBytes == 0 && !isEmpty) {
      onBufferLevelChange?.call(0);
    }

    return result;
  }

  /// Clear all buffered audio
  void clear({String? reason}) {
    final wasBuffered = _bufferedBytes;
    _writePos = 0;
    _readPos = 0;
    _bufferedBytes = 0;
    _pendingOddByte = null;
    _readyToPlayFired = false;

    debugPrint('🎵 [AudioBuffer] Cleared ${wasBuffered} bytes (${(wasBuffered * 1000) ~/ bytesPerSecond}ms) '
        'reason: ${reason ?? "unknown"}');

    onBufferLevelChange?.call(0);
  }

  /// Reset for a new session
  void reset() {
    clear(reason: 'session reset');
    _currentResponseId = null;
    _deltaCount = 0;
    _totalBytesReceived = 0;
    _responseComplete = false;
    _underrunCount = 0;
    _overrunCount = 0;
    _silenceBytesInserted = 0;
  }

  /// Get diagnostic info
  Map<String, dynamic> getDiagnostics() {
    return {
      'bufferedMs': bufferedMs,
      'bufferedBytes': _bufferedBytes,
      'capacityBytes': _buffer.length,
      'responseId': _currentResponseId,
      'deltaCount': _deltaCount,
      'totalBytesReceived': _totalBytesReceived,
      'responseComplete': _responseComplete,
      'underrunCount': _underrunCount,
      'overrunCount': _overrunCount,
      'silenceBytesInserted': _silenceBytesInserted,
      'readyToPlay': isReadyToPlay,
    };
  }
}
