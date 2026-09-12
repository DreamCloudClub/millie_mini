import 'dart:async';
import 'package:flutter/foundation.dart';

/// Voice state machine for conversation flow
enum VoiceSessionState {
  idle,
  listening,
  userSpeaking,
  waitingForAssistant,
  assistantBuffering,
  assistantSpeaking,
  interrupted,
  error,
}

/// Handles VAD events, barge-in detection, and interruption logic.
///
/// Key behaviors:
/// - Does NOT immediately clear audio on first speech_started
/// - Debounces VAD triggers to avoid false positives
/// - Confirms user speech before interrupting assistant
/// - Tracks state machine for conversation flow
class InterruptionController {
  // Configuration - relaxed settings for natural conversation pace
  static const int debounceMs = 600; // Wait longer before confirming interruption
  static const int minSpeechDurationMs = 400; // User must speak at least this long
  static const double vadThresholdRecommended = 0.85; // Higher = less sensitive to background noise

  // State
  VoiceSessionState _state = VoiceSessionState.idle;
  VoiceSessionState get state => _state;

  // Interruption tracking
  bool _possibleUserInterruption = false;
  DateTime? _speechStartTime;
  Timer? _debounceTimer;
  bool _interruptionConfirmed = false;

  // Callbacks
  void Function(VoiceSessionState state)? onStateChange;
  void Function()? onInterruptionConfirmed;
  void Function()? onInterruptionCancelled;
  void Function(String event, Map<String, dynamic> data)? onDiagnostic;

  InterruptionController();

  /// Whether assistant is currently outputting audio
  bool get isAssistantSpeaking =>
      _state == VoiceSessionState.assistantSpeaking ||
      _state == VoiceSessionState.assistantBuffering;

  /// Whether an interruption is being processed
  bool get isPossibleInterruption => _possibleUserInterruption;

  /// Whether interruption was confirmed (user is definitely speaking)
  bool get isInterruptionConfirmed => _interruptionConfirmed;

  /// Transition to a new state
  void setState(VoiceSessionState newState) {
    if (_state == newState) return;

    final oldState = _state;
    _state = newState;

    debugPrint('🎙️ [Interruption] State: ${oldState.name} → ${newState.name}');
    onStateChange?.call(newState);
    _emitDiagnostic('state_change', {
      'from': oldState.name,
      'to': newState.name,
    });
  }

  /// Handle VAD speech_started event from OpenAI
  ///
  /// Returns true if this should trigger immediate action (for backwards compat)
  /// Returns false if we're debouncing
  bool handleSpeechStarted() {
    _emitDiagnostic('speech_started', {
      'state': _state.name,
      'assistantSpeaking': isAssistantSpeaking,
      'alreadyDebouncing': _possibleUserInterruption,
    });

    // If not assistant speaking, just transition to user speaking
    if (!isAssistantSpeaking) {
      _speechStartTime = DateTime.now();
      setState(VoiceSessionState.userSpeaking);
      return false;
    }

    // Assistant is speaking - potential barge-in
    if (_possibleUserInterruption) {
      // Already debouncing, ignore duplicate
      debugPrint('🎙️ [Interruption] Already debouncing, ignoring duplicate speech_started');
      return false;
    }

    // Start debounce period
    _possibleUserInterruption = true;
    _speechStartTime = DateTime.now();
    _interruptionConfirmed = false;

    debugPrint('🎙️ [Interruption] Possible barge-in detected, starting ${debounceMs}ms debounce');

    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: debounceMs), () {
      _confirmInterruption();
    });

    return false; // Don't act immediately
  }

  /// Handle VAD speech_stopped event from OpenAI
  void handleSpeechStopped() {
    final speechDuration = _speechStartTime != null
        ? DateTime.now().difference(_speechStartTime!).inMilliseconds
        : 0;

    _emitDiagnostic('speech_stopped', {
      'state': _state.name,
      'speechDurationMs': speechDuration,
      'wasDebouncing': _possibleUserInterruption,
      'wasConfirmed': _interruptionConfirmed,
    });

    // If we were debouncing and speech stopped before confirmation
    if (_possibleUserInterruption && !_interruptionConfirmed) {
      if (speechDuration < minSpeechDurationMs) {
        // Too short - treat as false trigger
        debugPrint('🎙️ [Interruption] Speech too short (${speechDuration}ms), treating as false trigger');
        _cancelDebounce();
        return;
      }
    }

    // Normal speech stop handling
    if (_state == VoiceSessionState.userSpeaking) {
      setState(VoiceSessionState.waitingForAssistant);
    }

    _speechStartTime = null;
  }

  /// Confirm the interruption after debounce period
  void _confirmInterruption() {
    if (!_possibleUserInterruption) return;

    final speechDuration = _speechStartTime != null
        ? DateTime.now().difference(_speechStartTime!).inMilliseconds
        : 0;

    if (speechDuration < minSpeechDurationMs) {
      debugPrint('🎙️ [Interruption] Speech still too short at debounce end (${speechDuration}ms)');
      _cancelDebounce();
      return;
    }

    _interruptionConfirmed = true;
    debugPrint('🎙️ [Interruption] CONFIRMED after ${debounceMs}ms debounce (speech: ${speechDuration}ms)');

    _emitDiagnostic('interruption_confirmed', {
      'debounceMs': debounceMs,
      'speechDurationMs': speechDuration,
    });

    setState(VoiceSessionState.interrupted);
    onInterruptionConfirmed?.call();
  }

  /// Cancel the debounce (false trigger)
  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _possibleUserInterruption = false;
    _interruptionConfirmed = false;

    debugPrint('🎙️ [Interruption] Debounce cancelled (false trigger)');

    _emitDiagnostic('interruption_cancelled', {
      'reason': 'false_trigger',
    });

    onInterruptionCancelled?.call();
  }

  /// Manually cancel any pending interruption
  void cancelPendingInterruption() {
    if (_possibleUserInterruption) {
      _cancelDebounce();
    }
  }

  /// Reset after interruption is handled
  void resetInterruption() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _possibleUserInterruption = false;
    _interruptionConfirmed = false;
    _speechStartTime = null;
  }

  /// Mark that assistant audio has started buffering
  void markAssistantBuffering() {
    // Reset interruption flag so new response audio isn't blocked
    _interruptionConfirmed = false;
    _possibleUserInterruption = false;

    if (_state == VoiceSessionState.waitingForAssistant ||
        _state == VoiceSessionState.listening ||
        _state == VoiceSessionState.idle) {
      setState(VoiceSessionState.assistantBuffering);
    }
  }

  /// Mark that assistant audio playback has started
  void markAssistantSpeaking() {
    setState(VoiceSessionState.assistantSpeaking);
  }

  /// Mark that assistant audio has finished playing
  void markAssistantDone() {
    resetInterruption();
    setState(VoiceSessionState.listening);
  }

  /// Mark that we're starting to listen
  void markListening() {
    resetInterruption();
    setState(VoiceSessionState.listening);
  }

  /// Mark idle state
  void markIdle() {
    resetInterruption();
    setState(VoiceSessionState.idle);
  }

  /// Mark error state
  void markError() {
    resetInterruption();
    setState(VoiceSessionState.error);
  }

  void _emitDiagnostic(String event, Map<String, dynamic> data) {
    onDiagnostic?.call(event, {
      ...data,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Clean up resources
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Get recommended VAD configuration for OpenAI session
  /// These settings are relaxed to allow more natural conversation flow
  static Map<String, dynamic> getRecommendedVadConfig() {
    return {
      'type': 'server_vad',
      'threshold': vadThresholdRecommended,
      'prefix_padding_ms': 400,    // More audio context before detected speech
      'silence_duration_ms': 1000, // Wait longer before assuming user finished speaking
    };
  }
}
