import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import 'openai_service.dart';
import 'storage_service.dart';
import 'usage_tracking_service.dart';
import '../services/supabase_service.dart';
import 'note_tools_handler.dart';
import 'intent_router.dart';

/// Voice Pipeline Service
/// Implements the non-streaming voice pipeline:
/// MIC → VAD → STT → VALIDATION → LLM → TTS → PLAY AUDIO
class VoicePipelineService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final OpenAIService _openaiService;
  final StorageService _storageService;
  
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isContinuousMode = false;
  Completer<void>? _audioPlaybackCompleter; // Track current audio playback for cancellation
  bool _audioForceStopped = false; // Flag to prevent callbacks after force stop
  bool _isPaused = false;
  bool _isProcessing = false; // Guard to prevent parallel processing
  bool _isStopping = false; // Guard to prevent concurrent stop operations
  
  // Conversation context (stored for continuous flow)
  String? _currentAgentId;
  String? _currentPersonalityPrompt;
  String? _currentAiServiceId;
  String? _currentVoice;
  String? _currentUsername;
  String? _currentBio;
  String? _currentUserId;
  String? _currentUserEmail;
  AIServiceStatus? _currentSubscriptionStatus;
  Function()? _getConversationHistory;
  
  // VAD parameters
  StreamSubscription? _amplitudeSubscription;
  DateTime? _lastSpeechTime;
  DateTime? _firstSpeechTime;
  DateTime? _recordingStartTime; // Track when recording started
  Timer? _silenceTimer;
  Timer? _maxRecordingTimer;
  bool _hasDetectedSpeech = false;
  String? _currentRecordingPath;
  static const Duration _silenceThreshold = Duration(milliseconds: 2500); // Stop after 2.5s of silence (increased from 2s to avoid cutting off)
  static const Duration _maxRecordingDuration = Duration(seconds: 30); // Max recording time
  static const Duration _wakeWordSilenceThreshold = Duration(milliseconds: 800); // Shorter silence for wake word detection
  static const Duration _wakeWordMaxDuration = Duration(seconds: 5); // Much shorter max for wake word detection
  static const double _speechAmplitudeThreshold = -26.0; // dB threshold for speech detection (lowered from -20 to detect quieter speech)
  
  // Amplitude smoothing for noise filtering
  final List<double> _amplitudeHistory = []; // Store recent amplitude readings for smoothing
  static const int _amplitudeSmoothingSamples = 3; // Average over 3 samples
  static const int _sustainedSpeechRequired = 2; // Require 2 consecutive detections before triggering
  int _consecutiveSpeechDetections = 0; // Track consecutive speech detections
  
  
  // Wake word detection
  StreamSubscription? _wakeWordSubscription;
  bool _isWakeWordListening = false;
  
  // OpenAI Realtime API-based wake word service
  late final WakeWordService _wakeWordService;
  
  // Callbacks
  Function(VoiceState)? onStateChange;
  Function(String)? onTranscription;
  Function(String)? onResponse;
  Function(String)? onError;
  Function()? onWakeWordDetected;

  /// Called when TTS playback completes (for game/lesson mode FSM)
  Function()? onTTSPlaybackComplete;

  /// Called when transcription is ready for lesson mode (bypasses normal flow)
  /// Returns true if lesson mode handled it, false to continue normal processing
  bool Function(String)? onTranscriptionForLesson;

  // Reminder intent handler callback
  Future<String?> Function(String userInput, List<Map<String, dynamic>> reminders)? onProcessReminderIntent;

  // Note tools handler for AI note operations
  NoteToolsHandler? noteToolsHandler;

  /// Alternative LLM handler for conversation mode (e.g., OpenClaw)
  /// When set, this is used instead of the default OpenAI _callLLM for conversations.
  /// Returns null to fall back to default LLM, or response string if handled.
  ///
  /// Parameters match OpenAI's callChatCompletions:
  /// - userMessage: The user's transcribed message
  /// - systemPrompt: Instructions/personality for the AI
  /// - tools: Tool definitions for function calling
  /// - conversationHistory: Previous messages for context
  Future<String?> Function({
    required String userMessage,
    required String systemPrompt,
    List<Map<String, dynamic>>? tools,
    List<Map<String, dynamic>>? conversationHistory,
  })? alternativeLLMHandler;
  
  VoicePipelineService(StorageService storageService) 
      : _openaiService = OpenAIService(storageService),
        _storageService = storageService {
    _wakeWordService = WakeWordService(_openaiService);
  }
  
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get isWakeWordListening => _isWakeWordListening;

  /// Expose OpenAIService for spelling TTS player
  OpenAIService get openAIService => _openaiService;

  Future<bool> checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }
    
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Start listening with VAD (Voice Activity Detection) for continuous mode
  Future<void> startListening({
    bool continuousMode = false,
    String? agentId,
    String? personalityPrompt,
    String? aiServiceId,
    String? voice,
    String? username,
    String? bio,
    String? userId,
    String? userEmail,
    AIServiceStatus? subscriptionStatus,
    Function()? getConversationHistory,
  }) async {
    // Don't start if already recording (but allow if processing/playing since those should finish first)
    if (_isRecording) {
      debugPrint('Cannot start listening - already recording');
      return;
    }
    
    // Reset stopping flag to ensure clean state for new recording
    _isStopping = false;
    
    final hasPermission = await checkMicrophonePermission();
    if (!hasPermission) {
      onError?.call('Microphone permission denied');
      return;
    }

    try {
      // Check if recording is available
      if (!await _recorder.hasPermission()) {
        onError?.call('Microphone permission denied');
        return;
      }

      // Store context for continuous mode
      if (continuousMode) {
        _isContinuousMode = true;
        _currentAgentId = agentId;
        _currentPersonalityPrompt = personalityPrompt;
        _currentAiServiceId = aiServiceId;
        _currentVoice = voice;
        // Only update user info if provided (preserve existing values if not)
        if (username != null) _currentUsername = username;
        if (bio != null) _currentBio = bio;
        if (userId != null) _currentUserId = userId;
        if (userEmail != null) _currentUserEmail = userEmail;
        if (subscriptionStatus != null) _currentSubscriptionStatus = subscriptionStatus;
        if (getConversationHistory != null) _getConversationHistory = getConversationHistory;
      }

      onStateChange?.call(VoiceState.listening);
      
      final recordingPath = await _getRecordingPath();
      
      // Start recording with optimized settings for speech recognition
      // Use 16kHz sample rate to reduce file size (Whisper works great with this)
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000, // 16kHz - optimal for speech, reduces file size by ~3x vs 48kHz
          numChannels: 1, // Mono
        ),
        path: recordingPath,
      );
      _isRecording = true;
      _currentRecordingPath = recordingPath;
      _recordingStartTime = DateTime.now();
      
      debugPrint('Recording started${continuousMode ? " (continuous mode with VAD)" : ""} at: $recordingPath');
      
      // If continuous mode, start VAD monitoring
      if (continuousMode && _isContinuousMode) {
        _startVADMonitoring(recordingPath);
      }
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      onError?.call('Failed to start recording');
    }
  }
  
  /// Start VAD monitoring to auto-stop recording after silence (simplified - no chunking)
  void _startVADMonitoring(String recordingPath, {bool isWakeWordMode = false}) {
    _hasDetectedSpeech = false;
    _firstSpeechTime = null;
    _lastSpeechTime = DateTime.now();
    _currentRecordingPath = recordingPath;
    _recordingStartTime = DateTime.now(); // Track when VAD monitoring starts
    _amplitudeHistory.clear(); // Reset amplitude history
    _consecutiveSpeechDetections = 0; // Reset consecutive detections
    
    // Use shorter timeouts for wake word detection
    final currentSilenceThreshold = isWakeWordMode ? _wakeWordSilenceThreshold : _silenceThreshold;
    final currentMaxDuration = isWakeWordMode ? _wakeWordMaxDuration : _maxRecordingDuration;
    
    // Set max recording duration timer (safety fallback)
    _maxRecordingTimer = Timer(currentMaxDuration, () {
      if (_isRecording && _isContinuousMode && !_isStopping) {
        debugPrint('VAD: Max recording duration reached (${currentMaxDuration.inSeconds}s ${isWakeWordMode ? "wake word mode" : "normal mode"}) - FORCE STOPPING recording');
        // Force stop - this should not normally happen if VAD is working
        _amplitudeSubscription?.cancel();
        _silenceTimer?.cancel();
        _stopAndProcessRecording(recordingPath);
      } else {
        debugPrint('VAD: Max duration timer fired but not recording or not in continuous mode (recording: $_isRecording, continuous: $_isContinuousMode, stopping: $_isStopping)');
      }
    });
    
    // Monitor audio amplitude to detect speech and silence
    // This checks the microphone level every 200ms
    _amplitudeSubscription = Stream.periodic(
      const Duration(milliseconds: 200),
      (count) => count,
    ).asyncMap((_) async {
      if (!_isRecording || _isPaused) return null;
      try {
        // Get current audio amplitude (volume level) from microphone
        final amplitude = await _recorder.getAmplitude();
        return amplitude;
      } catch (e) {
        debugPrint('Error getting amplitude: $e');
        return null;
      }
    }).listen((amplitude) {
      if (amplitude == null || !_isRecording || _isPaused) return;
      
      // Amplitude smoothing: Add current reading to history
      _amplitudeHistory.add(amplitude.current);
      
      // Keep only the last N samples for smoothing
      if (_amplitudeHistory.length > _amplitudeSmoothingSamples) {
        _amplitudeHistory.removeAt(0);
      }
      
      // Calculate smoothed amplitude (average of recent samples)
      final smoothedAmplitude = _amplitudeHistory.isNotEmpty
          ? _amplitudeHistory.reduce((a, b) => a + b) / _amplitudeHistory.length
          : amplitude.current;
      
      // Check if smoothed amplitude is above threshold (indicates sustained speech-like activity)
      if (smoothedAmplitude > _speechAmplitudeThreshold) {
        // Increment consecutive speech detections
        _consecutiveSpeechDetections++;
        
        // Only trigger speech detection after sustained detections
        if (_consecutiveSpeechDetections >= _sustainedSpeechRequired) {
          if (!_hasDetectedSpeech) {
            // First time detecting sustained speech
            _hasDetectedSpeech = true;
            _firstSpeechTime = DateTime.now();
            debugPrint('VAD: Speech detected (smoothed: ${smoothedAmplitude.toStringAsFixed(1)} dB, raw: ${amplitude.current.toStringAsFixed(1)} dB, consecutive: $_consecutiveSpeechDetections)');
          }
          // Reset silence timer when sustained speech is detected (update frequently during speech)
          _lastSpeechTime = DateTime.now();
        } else if (_hasDetectedSpeech && _consecutiveSpeechDetections > 0) {
          // We've detected speech before, and we're building up to sustained detection again
          // Update last speech time to prevent premature silence detection during brief pauses
          _lastSpeechTime = DateTime.now();
        }
      } else {
        // Amplitude below threshold - reset consecutive detections
        if (_consecutiveSpeechDetections > 0) {
          debugPrint('VAD: Amplitude below threshold (${smoothedAmplitude.toStringAsFixed(1)} dB) - resetting consecutive detections');
        }
        _consecutiveSpeechDetections = 0;
        // Note: We don't update _lastSpeechTime here - let it stay at the last time we detected speech
        // The silence timer will count from _lastSpeechTime, so silence detection will work correctly
      }
    });
    
    // Monitor for silence after speech has been detected (simplified - single pass)
    _silenceTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      // Stop checking if paused or not recording
      if (!_isRecording || !_isContinuousMode || _isPaused) {
        timer.cancel();
        return;
      }
      
      // Check for silence after speech has been detected
      if (_hasDetectedSpeech && _lastSpeechTime != null) {
        final silenceDuration = DateTime.now().difference(_lastSpeechTime!);
        
        // Use shorter silence threshold for wake word mode  
        final currentSilenceThreshold = _isWakeWordListening ? _wakeWordSilenceThreshold : _silenceThreshold;
        
        // Stop recording when silence threshold is reached
        if (silenceDuration >= currentSilenceThreshold) {
          debugPrint('VAD: Silence detected (${silenceDuration.inMilliseconds}ms >= ${currentSilenceThreshold.inMilliseconds}ms threshold) - stopping recording (${_isWakeWordListening ? "wake word mode" : "normal mode"})');
          timer.cancel();
          _amplitudeSubscription?.cancel();
          // Double-check we're still recording and not already stopping
          if (_isRecording && !_isStopping) {
            _stopAndProcessRecording(recordingPath);
          } else {
            debugPrint('VAD: WARNING - Silence detected but recorder was already stopped or stopping (recording: $_isRecording, stopping: $_isStopping)');
          }
          return;
        }
      } else if (!_hasDetectedSpeech) {
        // Waiting for speech - log occasionally
        final timeSinceStart = _lastSpeechTime != null 
            ? DateTime.now().difference(_lastSpeechTime!) 
            : Duration.zero;
        if (timeSinceStart.inMilliseconds % 2000 < 200) { // Log every 2 seconds
          debugPrint('VAD: Waiting for speech detection...');
        }
      }
    });
  }
  
  /// Stop recording and process in simple single-pass mode (no chunking)
  Future<void> _stopAndProcessRecording(String recordingPath) async {
    // Guard: Prevent concurrent stop operations
    if (_isStopping || !_isRecording) {
      debugPrint('_stopAndProcessRecording: Already stopping or not recording (stopping: $_isStopping, recording: $_isRecording)');
      return;
    }
    
    // Set stopping flag IMMEDIATELY to prevent concurrent calls
    _isStopping = true;
    
    // Cancel all timers FIRST to prevent them from firing again
    _amplitudeSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordingTimer?.cancel();
    
    // Don't process if already processing (but allow processing to continue)
    if (_isProcessing) {
      debugPrint('Cannot process - already processing, stopping recording without processing');
      // Stop recording but don't process
      try {
        // Set _isRecording to false BEFORE stopping to prevent other timers from interfering
        _isRecording = false;
        final path = await _recorder.stop();
        _currentRecordingPath = null;
        debugPrint('VAD: Recording stopped (during processing): $path');
      } catch (e) {
        debugPrint('Error stopping recorder: $e');
        _isRecording = false;
        _currentRecordingPath = null;
      } finally {
        _isStopping = false;
      }
      // Return to listening state if in continuous mode and not paused
      if (_isContinuousMode && !_isPaused) {
        onStateChange?.call(VoiceState.listening);
      }
      return;
    }
    
    // Stop recording - set flag BEFORE awaiting to prevent race conditions
    try {
      // Set _isRecording to false BEFORE stopping to prevent other timers from interfering
      _isRecording = false;
      debugPrint('VAD: Stopping recorder (flag set to false)...');
      final path = await _recorder.stop();
      _currentRecordingPath = null;
      debugPrint('VAD: Recording stopped: $path');
      
      // Wait a brief moment to ensure file is fully flushed to disk
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Log file size and recording duration to diagnose large file issues
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          // Verify file is stable (size hasn't changed)
          final initialSize = await file.length();
          await Future.delayed(const Duration(milliseconds: 50));
          final finalSize = await file.length();
          
          if (initialSize != finalSize) {
            debugPrint('WARNING: File size changed during flush check (${initialSize} -> ${finalSize} bytes) - waiting longer');
            await Future.delayed(const Duration(milliseconds: 200));
          }
          
          final fileSize = await file.length();
          final fileSizeKB = (fileSize / 1024).toStringAsFixed(1);
          final recordingStartTime = _recordingStartTime;
          final recordingDuration = recordingStartTime != null 
              ? DateTime.now().difference(recordingStartTime).inMilliseconds 
              : null;
          debugPrint('VAD: Recording stopped - file size: $fileSizeKB KB ($fileSize bytes)${recordingDuration != null ? ", duration: ${recordingDuration}ms" : ""}');
          
          // Validate WAV file header
          try {
            final headerBytes = await file.openRead(0, 44).toList();
            if (headerBytes.isNotEmpty && headerBytes[0].length >= 44) {
              final header = headerBytes.expand((e) => e).toList();
              final riff = String.fromCharCodes(header.sublist(0, 4));
              final wave = String.fromCharCodes(header.sublist(8, 12));
              if (riff != 'RIFF' || wave != 'WAVE') {
                debugPrint('WARNING: Invalid WAV header detected (RIFF: $riff, WAVE: $wave)');
              } else {
                debugPrint('VAD: WAV header validated successfully');
              }
            }
          } catch (e) {
            debugPrint('WARNING: Could not validate WAV header: $e');
          }
          
          if (fileSize > 500 * 1024) { // Warn if > 500KB
            debugPrint('WARNING: Recording file is unusually large (>500KB) - may indicate recorder not stopping properly or high sample rate');
          }
          if (recordingDuration != null && recordingDuration > 10000) { // Warn if > 10 seconds
            debugPrint('WARNING: Recording duration is unusually long (${(recordingDuration / 1000).toStringAsFixed(1)}s) - VAD may not be detecting silence properly');
          }
        } else {
          debugPrint('ERROR: Recording file does not exist after stop: $path');
        }
      }
      _recordingStartTime = null; // Reset
      
      // Only process if we got a valid path and have required context
      if (path != null && _isContinuousMode && 
          _currentAgentId != null && 
          _currentPersonalityPrompt != null &&
          _currentAiServiceId != null &&
          _currentVoice != null) {
        
        // Simple single-pass processing: STT → LLM → TTS → Play
        await _processSingleRecording(
          path,
          agentId: _currentAgentId!,
          personalityPrompt: _currentPersonalityPrompt!,
          aiServiceId: _currentAiServiceId!,
          voice: _currentVoice!,
        );
      } else if (!_isContinuousMode) {
        // Not in continuous mode, just return to listening
        onStateChange?.call(VoiceState.listening);
      }
    } catch (e, stackTrace) {
      debugPrint('Error stopping recording: $e');
      debugPrint('Stack trace: $stackTrace');
      _isRecording = false;
      _currentRecordingPath = null;
      onError?.call('Failed to stop recording');
    } finally {
      // Always clear stopping flag
      _isStopping = false;
    }
  }
  
  /// Process a single recording in simple mode: STT → LLM → TTS → Play
  Future<void> _processSingleRecording(
    String recordingPath, {
    required String agentId,
    required String personalityPrompt,
    required String aiServiceId,
    required String voice,
  }) async {
    // Prevent parallel processing
    if (_isProcessing) {
      debugPrint('Already processing - ignoring duplicate request');
      return;
    }
    
    _isProcessing = true;
    
    // Don't set state to processing if we're paused in wake word mode (stay in paused state)
    // Only set to processing if we're NOT in wake word detection mode
    if (!(_isPaused && _isWakeWordListening)) {
      onStateChange?.call(VoiceState.processing);
    } else {
      // We're in wake word mode - keep state as paused (don't change it)
      debugPrint('Staying in paused state during wake word check');
    }
    
    try {
      // Step 1: Speech to Text
      final transcription = await _speechToText(recordingPath);
      
      if (transcription == null || transcription.isEmpty) {
        debugPrint('No transcription - returning to listening');
        _isProcessing = false;
        if (_isPaused && _isWakeWordListening) {
          // Stay paused and restart wake word listening
          _restartWakeWordListening();
        } else {
          onStateChange?.call(VoiceState.listening);
        }
        return;
      }
      
      debugPrint('Transcription received: $transcription');
      
      // If paused, ignore all transcriptions (only manual resume via play/double-tap)
      if (_isPaused) {
        debugPrint('Paused - ignoring transcription (only manual resume via play/double-tap): "$transcription"');
        _isProcessing = false; // Reset processing flag
        onStateChange?.call(VoiceState.paused); // Ensure UI knows we're paused
        return;
      }
      
      // Notify transcription (adds to conversation)
      onTranscription?.call(transcription);
      
      // Check for reminder intent handling (if callback is set)
      String? reminderResponse;
      if (onProcessReminderIntent != null) {
        try {
          // Get current reminders list (convert to map for callback)
          // This will be provided by VoiceProvider
          reminderResponse = await onProcessReminderIntent!(transcription, []);
          if (reminderResponse != null && reminderResponse.isNotEmpty) {
            debugPrint('VoicePipeline: ReminderIntentHandler returned response: "$reminderResponse"');
            debugPrint('VoicePipeline: Using reminder handler response, SKIPPING LLM call');
            // Use reminder handler response instead of LLM
            onResponse?.call(reminderResponse);
            
            // Generate TTS and play
            // Note: Reminder flow is ended in the handler itself via endFlow(),
            // so subsequent inputs will go through normal LLM flow
            final audioChunks = await _generateTTSChunks(reminderResponse, voice);
            if (audioChunks.isEmpty) {
              onError?.call('Failed to generate speech');
              onStateChange?.call(VoiceState.listening);
              return;
            }
            
            // Continue in normal conversation mode after reminder flow ends
            await _playAudioChunks(audioChunks, autoResumeListening: _isContinuousMode, forcePlay: true);
            return; // CRITICAL: Skip LLM call when reminder handler has a response
          } else {
            debugPrint('VoicePipeline: ReminderIntentHandler returned null/empty, continuing to LLM');
          }
        } catch (e, stackTrace) {
          debugPrint('VoicePipeline: ERROR in reminder intent handler: $e');
          debugPrint('VoicePipeline: Stack trace: $stackTrace');
          // Continue to normal LLM flow on error
        }
      }
      
      // No voice command pause - only manual pause via button/double-tap
      
      // Fetch conversation history (now includes current user message)
      final conversationHistory = _getConversationHistory?.call() ?? [];
      debugPrint('Conversation history has ${conversationHistory.length} messages');
      
      // Build enhanced system prompt
      final enhancedSystemPrompt = _buildSystemPrompt(personalityPrompt);

      // Step 2: Call LLM
      final response = await _callLLM(
        transcription: transcription,
        personalityPrompt: enhancedSystemPrompt,
        conversationHistory: conversationHistory,
      );

      // Check if paused while waiting for LLM - abort if so
      if (_isPaused) {
        debugPrint('Paused during LLM call - aborting response playback');
        _isProcessing = false;
        onStateChange?.call(VoiceState.paused);
        return;
      }

      if (response == null || response.isEmpty) {
        onError?.call('Failed to get AI response');
        onStateChange?.call(VoiceState.listening);
        return;
      }
      
      debugPrint('LLM response received: ${response.substring(0, response.length > 100 ? 100 : response.length)}...');
      onResponse?.call(response);

      // Check if paused before TTS - abort if so
      if (_isPaused) {
        debugPrint('Paused before TTS - aborting response playback');
        _isProcessing = false;
        onStateChange?.call(VoiceState.paused);
        return;
      }

      // Step 3: Generate TTS chunks
      final audioChunks = await _generateTTSChunks(response, voice);
      if (audioChunks.isEmpty) {
        onError?.call('Failed to generate speech');
        onStateChange?.call(VoiceState.listening);
        return;
      }

      // Check if paused after TTS generation - abort if so (before playback starts)
      if (_isPaused) {
        debugPrint('Paused after TTS generation - aborting playback');
        _isProcessing = false;
        onStateChange?.call(VoiceState.paused);
        return;
      }

      // Step 4: Play audio chunks and resume listening
      // forcePlay: true ensures audio completes once started (pause checks above prevent starting if paused)
      await _playAudioChunks(audioChunks, autoResumeListening: _isContinuousMode, forcePlay: true);
      
    } catch (e) {
      debugPrint('Error processing recording: $e');
      onError?.call('An error occurred while processing');
      onStateChange?.call(VoiceState.listening);
      
      // Try to resume listening if in continuous mode
      if (_isContinuousMode) {
        await Future.delayed(const Duration(milliseconds: 500));
        await startListening(
          continuousMode: true,
          agentId: agentId,
          personalityPrompt: personalityPrompt,
          aiServiceId: aiServiceId,
          voice: voice,
          username: _currentUsername,
          bio: _currentBio,
          userId: _currentUserId,
          userEmail: _currentUserEmail,
          subscriptionStatus: _currentSubscriptionStatus,
          getConversationHistory: _getConversationHistory,
        );
      }
    } finally {
      _isProcessing = false; // Always clear processing flag
    }
  }
  
  /// Process combined transcription from multiple segments (DEPRECATED - keeping for compatibility)
  Future<void> _processCombinedTranscription(
    String transcription, {
    required String agentId,
    required String personalityPrompt,
    required String aiServiceId,
    required String voice,
    required List<Map<String, String>> conversationHistory,
  }) async {
    onStateChange?.call(VoiceState.processing);
    
    try {
      // Note: transcription already notified before this method was called
      // Don't call onTranscription again to avoid duplicate messages
      
      // No voice command pause - only manual pause via button/double-tap
      
      // Build enhanced system prompt to prevent premature endings
      final enhancedSystemPrompt = _buildSystemPrompt(personalityPrompt);
      
      // Call LLM with combined transcription
      final response = await _callLLM(
        transcription: transcription,
        personalityPrompt: enhancedSystemPrompt,
        conversationHistory: conversationHistory,
      );
      
      if (response == null || response.isEmpty) {
        onError?.call('Failed to get AI response');
        onStateChange?.call(VoiceState.listening);
        return;
      }
      
      onResponse?.call(response);

      // Generate TTS chunks in parallel
      final audioChunks = await _generateTTSChunks(response, voice);
      if (audioChunks.isEmpty) {
        onError?.call('Failed to generate speech');
        onStateChange?.call(VoiceState.listening);
        return;
      }

      // Play all audio chunks sequentially
      await _playAudioChunks(audioChunks, autoResumeListening: _isContinuousMode, forcePlay: true);

    } catch (e) {
      debugPrint('Pipeline error: $e');
      onError?.call('An error occurred');
      
      if (_isContinuousMode) {
        await startListening(
          continuousMode: true,
          agentId: _currentAgentId,
          personalityPrompt: _currentPersonalityPrompt,
          aiServiceId: _currentAiServiceId,
          voice: _currentVoice,
          username: _currentUsername,
          bio: _currentBio,
          userId: _currentUserId,
          userEmail: _currentUserEmail,
          subscriptionStatus: _currentSubscriptionStatus,
          getConversationHistory: _getConversationHistory,
        );
      } else {
        onStateChange?.call(VoiceState.listening);
      }
    }
  }
  
  /// Stop recording and automatically process in continuous mode

  Future<String?> stopListening() async {
    if (!_isRecording) return null;
    
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      debugPrint('Recording stopped: $path');
      return path;
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> processAudio(String audioPath, {
    required String agentId,
    required String personalityPrompt,
    required String aiServiceId,
    required String voice,
    required List<Map<String, String>> conversationHistory,
  }) async {
    onStateChange?.call(VoiceState.processing);
    
    try {
      // Step 1: STT (Speech to Text)
      final transcription = await _speechToText(audioPath);
      if (transcription == null || transcription.isEmpty) {
        debugPrint('No speech detected');
        onStateChange?.call(VoiceState.listening);
        return;
      }
      
      onTranscription?.call(transcription);
      
      // Step 2: If paused, only check for resume triggers (like "hey millie")
      if (_isPaused) {
        if (_checkResumeTriggers(transcription)) {
          debugPrint('Resume trigger detected while paused: "$transcription"');
          onWakeWordDetected?.call();
          return;
        } else {
          // Not a wake word, ignore this transcription
          debugPrint('Ignoring transcription while paused: "$transcription"');
          return;
        }
      }
      
      // No voice command pause - only manual pause via button/double-tap
      
      // Build enhanced system prompt to prevent premature endings
      final enhancedSystemPrompt = _buildSystemPrompt(personalityPrompt);
      
      // Fetch updated conversation history (includes current user message from onTranscription callback)
      final updatedHistory = conversationHistory.isNotEmpty 
          ? conversationHistory 
          : (_getConversationHistory?.call() ?? []);
      debugPrint('LLM conversation history has ${updatedHistory.length} messages');
      
      // Step 3: Call LLM (non-streaming)
      final response = await _callLLM(
        transcription: transcription,
        personalityPrompt: enhancedSystemPrompt,
        conversationHistory: updatedHistory,
      );
      
      if (response == null || response.isEmpty) {
        onError?.call('Failed to get AI response');
        onStateChange?.call(VoiceState.listening);
        return;
      }
      
      onResponse?.call(response);
      
      // Step 4: Split response into chunks and generate TTS in parallel
      final audioChunks = await _generateTTSChunks(response, voice);
      if (audioChunks.isEmpty) {
        onError?.call('Failed to generate speech');
        onStateChange?.call(VoiceState.listening);
        return;
      }
      
      // Step 5: Play all audio chunks sequentially (recording is already stopped)
      await _playAudioChunks(audioChunks, autoResumeListening: _isContinuousMode, forcePlay: true);
      
    } catch (e) {
      debugPrint('Pipeline error: $e');
      onError?.call('An error occurred');
      
      // In continuous mode, still try to resume listening after error (immediately)
      if (_isContinuousMode) {
        await startListening(
          continuousMode: true,
          agentId: _currentAgentId,
          personalityPrompt: _currentPersonalityPrompt,
          aiServiceId: _currentAiServiceId,
          voice: _currentVoice,
          username: _currentUsername,
          bio: _currentBio,
          userId: _currentUserId,
          userEmail: _currentUserEmail,
          subscriptionStatus: _currentSubscriptionStatus,
          getConversationHistory: _getConversationHistory,
        );
      } else {
        onStateChange?.call(VoiceState.listening);
      }
    }
  }
  
  /// Pause continuous mode (stop recording but keep context)
  Future<void> pauseContinuousMode() async {
    _isPaused = true;
    _audioForceStopped = true; // Stop any ongoing playback callbacks
    _isProcessing = false; // Reset processing flag when pausing
    _isStopping = false; // Reset stopping flag to prevent stale state
    debugPrint('Pausing continuous mode...');

    // Complete any pending audio playback completer
    if (_audioPlaybackCompleter != null && !_audioPlaybackCompleter!.isCompleted) {
      _audioPlaybackCompleter!.complete();
      _audioPlaybackCompleter = null;
    }

    // Cancel all timers
    _amplitudeSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordingTimer?.cancel();

    // Stop audio playback
    if (_isPlaying) {
      try {
        await _player.stop();
        _isPlaying = false;
      } catch (e) {
        debugPrint('Error stopping audio: $e');
        _isPlaying = false;
      }
    }

    // Stop recording
    if (_isRecording) {
      try {
        await _recorder.stop();
        _isRecording = false;
      } catch (e) {
        debugPrint('Error stopping recorder: $e');
        _isRecording = false;
      }
    }

    // CRITICAL: Notify UI of state change to paused
    onStateChange?.call(VoiceState.paused);
    debugPrint('Continuous mode paused');
  }

  /// Resume continuous mode (restart listening)
  Future<void> resumeContinuousMode() async {
    if (!_isContinuousMode) return;

    _isPaused = false;
    _audioForceStopped = false; // Reset force stop flag for new activity
    _isProcessing = false; // Reset processing flag when resuming
    _isStopping = false; // Reset stopping flag to ensure clean state
    stopWakeWordDetection();

    // Restart listening
    if (!_isRecording) {
      await startListening(
        continuousMode: true,
        agentId: _currentAgentId,
        personalityPrompt: _currentPersonalityPrompt,
        aiServiceId: _currentAiServiceId,
        voice: _currentVoice,
        username: _currentUsername,
        bio: _currentBio,
        userId: _currentUserId,
        userEmail: _currentUserEmail,
        subscriptionStatus: _currentSubscriptionStatus,
        getConversationHistory: _getConversationHistory,
      );
    }

    debugPrint('Continuous mode resumed');
  }
  
  /// Start sleep mode - just sets state, waiting for manual play/double-tap
  Future<void> startSleepMode({Function()? onWakeWordDetected}) async {
    debugPrint('Starting sleep mode - waiting for play button or double-tap');
    
    // Set state to sleep (just a waiting state, no wake word detection)
    onStateChange?.call(VoiceState.sleep);
  }
  
  /// Stop sleep mode
  Future<void> stopSleepMode() async {
    debugPrint('Stopping sleep mode');
    // No cleanup needed - sleep mode is just a state
  }
  
  /// Start wake word detection for unpausing (legacy method using STT - uses tokens)
  void startWakeWordDetection({Function()? onWakeWordDetected}) {
    if (_isWakeWordListening) {
      debugPrint('Wake word detection already active - skipping');
      return;
    }
    
    this.onWakeWordDetected = onWakeWordDetected;
    debugPrint('Wake word detection callback set: ${onWakeWordDetected != null}');
    _isWakeWordListening = true;
    
    debugPrint('Wake word detection started (listening for "hey millie" - uses STT/TOKENS)');
    
    // Start continuous listening in wake-word-only mode
    // It will check transcriptions for wake words via processAudio
    _startWakeWordListening();
  }
  
  /// Stop wake word detection
  void stopWakeWordDetection() {
    if (!_isWakeWordListening) return;
    
    _isWakeWordListening = false;
    _wakeWordSubscription?.cancel();
    _wakeWordSubscription = null;
    
    debugPrint('Wake word detection stopped');
  }
  
  /// Start listening for wake word (continuously records and checks for wake phrase)
  Future<void> _startWakeWordListening() async {
    // When paused, we continue listening but only check for wake words
    // Restart recording for wake word detection
    if (!_isRecording && _isContinuousMode && _isPaused) {
      final recordingPath = await _getRecordingPath();
      
      try {
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: recordingPath,
        );
        _isRecording = true;
        _startVADMonitoring(recordingPath, isWakeWordMode: true);
        debugPrint('Wake word listening started (shorter timeouts: ${_wakeWordMaxDuration.inSeconds}s max, ${_wakeWordSilenceThreshold.inMilliseconds}ms silence)');
      } catch (e) {
        debugPrint('Failed to start wake word listening: $e');
      }
    }
  }
  
  /// Restart wake word listening (after checking a transcription that didn't contain wake word)
  Future<void> _restartWakeWordListening() async {
    if (!_isWakeWordListening || !_isPaused) return;
    
    debugPrint('Restarting wake word listening...');
    // Small delay before restarting
    await Future.delayed(const Duration(milliseconds: 300));
    await _startWakeWordListening();
  }
  
  /// Force stop any audio playback immediately
  Future<void> forceStopAudio() async {
    debugPrint('Force stopping audio playback');
    _audioForceStopped = true; // Set flag to prevent callbacks
    try {
      // Complete any pending audio playback completer first
      if (_audioPlaybackCompleter != null && !_audioPlaybackCompleter!.isCompleted) {
        _audioPlaybackCompleter!.complete();
        _audioPlaybackCompleter = null;
      }
      // Stop and release to ensure immediate silence
      await _player.stop();
      await _player.release();
      _isPlaying = false;
    } catch (e) {
      debugPrint('Error force stopping audio: $e');
      _isPlaying = false;
    }
  }

  /// Stop continuous mode completely - full context wipe
  Future<void> stopContinuousMode() async {
    debugPrint('Stopping continuous mode - full context wipe');

    // Cancel all timers
    _amplitudeSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordingTimer?.cancel();
    stopWakeWordDetection();

    // Stop audio playback
    try {
      await _player.stop();
      await _player.release();
      _isPlaying = false;
    } catch (e) {
      debugPrint('Error stopping audio: $e');
      _isPlaying = false;
    }
    
    // Stop recording
    if (_isRecording) {
      try {
        await _recorder.stop();
        _isRecording = false;
      } catch (e) {
        debugPrint('Error stopping recorder: $e');
        _isRecording = false;
      }
    }
    
    // Complete context wipe - reset everything
    _isContinuousMode = false;
    _isPaused = false; // Reset paused state
    _isProcessing = false; // Reset processing flag
    _hasDetectedSpeech = false;
    _firstSpeechTime = null;
    _lastSpeechTime = null;
    _currentRecordingPath = null;
    _currentAgentId = null;
    _currentPersonalityPrompt = null;
    _currentAiServiceId = null;
    _currentVoice = null;
    _getConversationHistory = null;
    
    debugPrint('Continuous mode stopped - context wiped');
  }

  bool _checkPauseTriggers(String transcription) {
    final normalized = transcription.toLowerCase().trim();
    for (final trigger in VoiceTriggers.pauseTriggers) {
      // Check if transcription contains the pause trigger anywhere in the text
      if (normalized == trigger || 
          normalized.startsWith('$trigger ') ||
          normalized.contains(' $trigger') ||
          normalized.contains(' $trigger ')) {
        debugPrint('Pause trigger detected: "$trigger" in "$normalized"');
        return true;
      }
    }
    return false;
  }
  
  bool _checkResumeTriggers(String transcription) {
    final normalized = transcription.toLowerCase().trim();
    // Remove punctuation for matching (keep spaces)
    final cleaned = normalized.replaceAll(RegExp(r'[.,!?;:]'), ' ');
    
    for (final trigger in VoiceTriggers.resumeTriggers) {
      // Check if transcription contains the resume trigger (with flexible word boundaries)
      if (normalized == trigger ||
          normalized.startsWith('$trigger ') ||
          normalized.startsWith('$trigger.') ||
          normalized.startsWith('$trigger,') ||
          normalized.contains(' $trigger ') ||
          normalized.contains(' $trigger.') ||
          normalized.contains(' $trigger,') ||
          normalized.contains('$trigger') ||
          cleaned.contains(trigger)) {
        debugPrint('Resume trigger detected: "$trigger" in "$normalized"');
        return true;
      }
    }
    return false;
  }
  
  /// Configure pipeline for text mode (without starting voice recording)
  /// Used when user starts with text input before voice session is activated
  void configureForTextMode({
    String? agentId,
    String? personalityPrompt,
    String? aiServiceId,
    String? voice,
    String? username,
    String? bio,
    String? userId,
    String? userEmail,
    AIServiceStatus? subscriptionStatus,
    List<Map<String, String>> Function()? getConversationHistory,
  }) {
    // Only configure if not already configured
    if (_currentPersonalityPrompt == null || _currentVoice == null) {
      debugPrint('Configuring pipeline for text mode');
      _currentAgentId = agentId;
      _currentPersonalityPrompt = personalityPrompt;
      _currentAiServiceId = aiServiceId;
      _currentVoice = voice;
      _currentUsername = username;
      _currentBio = bio;
      _currentUserId = userId;
      _currentUserEmail = userEmail;
      _currentSubscriptionStatus = subscriptionStatus;
      _getConversationHistory = getConversationHistory;
      _isContinuousMode = true; // Enable for proper resume later
    }
  }
  
  /// Process a text message directly (bypasses STT)
  /// Used by ChatPage for text input mode
  Future<String?> processTextMessage(
    String text, {
    bool playAudio = true,
    String? voice,
  }) async {
    if (text.trim().isEmpty) return null;
    
    debugPrint('Processing text message: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
    
    try {
      // Ensure we have context (should be set from startSession)
      if (_currentPersonalityPrompt == null) {
        debugPrint('Warning: No personality prompt set for text message');
      }
      
      // Build system prompt
      final systemPrompt = _buildSystemPrompt(_currentPersonalityPrompt ?? '');
      
      // Get conversation history callback
      final conversationHistory = _getConversationHistory?.call() ?? [];
      
      // Call LLM
      final response = await _callLLM(
        transcription: text,
        personalityPrompt: systemPrompt,
        conversationHistory: conversationHistory.cast<Map<String, dynamic>>(),
      );
      
      if (response == null) {
        debugPrint('No response from LLM');
        onError?.call('Failed to get response');
        return null;
      }
      
      debugPrint('LLM response: ${response.substring(0, response.length > 50 ? 50 : response.length)}...');
      
      // Show text response immediately (before TTS)
      onResponse?.call(response);

      // Optionally play TTS
      final voiceToUse = _currentVoice ?? voice ?? 'alloy';
      debugPrint('TTS playback check: playAudio=$playAudio, voice=$voiceToUse');
      if (playAudio) {
        onStateChange?.call(VoiceState.speaking);
        debugPrint('Generating TTS audio with voice: $voiceToUse');
        final audioPath = await _textToSpeech(response, voiceToUse);
        
        debugPrint('TTS audio path: $audioPath');
        if (audioPath != null) {
          // Play the audio
          debugPrint('Playing audio file...');
          try { await _player.stop(); } catch (_) {}
          _isPlaying = true;
          
          final completer = Completer<void>();
          StreamSubscription<void>? subscription;
          subscription = _player.onPlayerComplete.listen((_) {
            if (!completer.isCompleted) {
              completer.complete();
              subscription?.cancel();
            }
          });
          
          await _player.play(DeviceFileSource(audioPath));
          debugPrint('Waiting for audio completion...');
          await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
            subscription?.cancel();
          });
          _isPlaying = false;
          debugPrint('Audio playback complete');

          // Execute any pending navigation after TTS completes
          noteToolsHandler?.checkAndExecutePendingNavigation();
        } else {
          debugPrint('ERROR: TTS returned null audio path');
          // Still execute pending navigation even if TTS failed
          noteToolsHandler?.checkAndExecutePendingNavigation();
        }
      } else {
        debugPrint('Skipping TTS: playAudio=$playAudio');
        // Execute pending navigation immediately if no audio
        noteToolsHandler?.checkAndExecutePendingNavigation();
      }

      return response;
      
    } catch (e) {
      debugPrint('Error processing text message: $e');
      onError?.call('Failed to process message');
      return null;
    }
  }
  
  /// Play text as speech (for reminder handler responses in text mode)
  Future<void> playTextToSpeech(String text, String voice) async {
    try {
      debugPrint('Playing TTS for text: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
      onStateChange?.call(VoiceState.speaking);
      final audioPath = await _textToSpeech(text, voice);

      if (audioPath != null) {
        try { await _player.stop(); } catch (_) {}
        _isPlaying = true;

        final completer = Completer<void>();
        StreamSubscription<void>? subscription;
        subscription = _player.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
            subscription?.cancel();
          }
        });

        await _player.play(DeviceFileSource(audioPath));
        await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
          subscription?.cancel();
        });
        _isPlaying = false;
        debugPrint('TTS playback complete');

        // Fire TTS completion callback for lesson mode FSM
        onTTSPlaybackComplete?.call();
      }
    } catch (e) {
      debugPrint('Error playing TTS: $e');
    }
  }

  /// Play TTS for lesson mode (no auto-resume, fires completion callback)
  Future<void> playTTSForLesson(String text, String voice) async {
    try {
      debugPrint('Playing lesson TTS: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
      onStateChange?.call(VoiceState.speaking);
      final audioPath = await _textToSpeech(text, voice);

      if (audioPath != null) {
        try { await _player.stop(); } catch (_) {}
        _isPlaying = true;

        final completer = Completer<void>();
        StreamSubscription<void>? subscription;
        subscription = _player.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
            subscription?.cancel();
          }
        });

        await _player.play(DeviceFileSource(audioPath));
        await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
          subscription?.cancel();
        });
        _isPlaying = false;
        debugPrint('Lesson TTS playback complete');

        // Wait a moment before callback
        await Future.delayed(const Duration(milliseconds: 300));

        // Fire TTS completion callback for lesson mode FSM
        onTTSPlaybackComplete?.call();
      } else {
        // No audio path - still fire callback so FSM can proceed
        onTTSPlaybackComplete?.call();
      }
    } catch (e) {
      debugPrint('Error playing lesson TTS: $e');
      // Still fire callback on error so FSM doesn't get stuck
      onTTSPlaybackComplete?.call();
    }
  }

  /// Play an audio file for lesson mode (cached TTS, no generation)
  Future<void> playAudioFileForLesson(String audioPath) async {
    _audioForceStopped = false; // Reset flag at start
    try {
      debugPrint('Playing cached audio: $audioPath');
      onStateChange?.call(VoiceState.speaking);

      try { await _player.stop(); } catch (_) {}
      _isPlaying = true;

      // Use tracked completer so forceStopAudio can cancel it
      _audioPlaybackCompleter = Completer<void>();
      StreamSubscription<void>? subscription;
      subscription = _player.onPlayerComplete.listen((_) {
        if (_audioPlaybackCompleter != null && !_audioPlaybackCompleter!.isCompleted) {
          _audioPlaybackCompleter!.complete();
          subscription?.cancel();
        }
      });

      await _player.play(DeviceFileSource(audioPath));
      await _audioPlaybackCompleter!.future.timeout(const Duration(seconds: 120), onTimeout: () {
        subscription?.cancel();
      });
      subscription.cancel();
      _audioPlaybackCompleter = null;
      _isPlaying = false;
      debugPrint('Cached audio playback complete');

      // Skip callback if we were force-stopped
      if (_audioForceStopped) {
        debugPrint('Audio was force-stopped - skipping callback');
        return;
      }

      // Wait a moment before callback
      await Future.delayed(const Duration(milliseconds: 300));

      // Fire TTS completion callback for lesson mode FSM
      onTTSPlaybackComplete?.call();
    } catch (e) {
      debugPrint('Error playing cached audio: $e');
      _audioPlaybackCompleter = null;
      // Still fire callback on error so FSM doesn't get stuck (unless force-stopped)
      if (!_audioForceStopped) {
        onTTSPlaybackComplete?.call();
      }
    }
  }

  /// Generate TTS audio and play it, returning the local file path for caching
  Future<String?> generateAndPlayTTS(String text, String voice) async {
    try {
      debugPrint('Generating TTS for caching: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');

      // Reset force stop flag for new playback
      _audioForceStopped = false;

      onStateChange?.call(VoiceState.speaking);

      final audioPath = await _textToSpeech(text, voice);
      if (audioPath == null) {
        debugPrint('Failed to generate TTS audio');
        return null;
      }

      // Check if force stopped during generation
      if (_audioForceStopped) {
        debugPrint('TTS aborted - force stopped during generation');
        return audioPath; // Return path but don't play
      }

      // Play the audio
      try { await _player.stop(); } catch (_) {}
      _isPlaying = true;

      final completer = Completer<void>();
      _audioPlaybackCompleter = completer;
      StreamSubscription<void>? subscription;
      subscription = _player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted && !_audioForceStopped) {
          completer.complete();
          subscription?.cancel();
        }
      });

      await _player.play(DeviceFileSource(audioPath));
      await completer.future.timeout(const Duration(seconds: 120), onTimeout: () {
        subscription?.cancel();
      });

      _audioPlaybackCompleter = null;
      _isPlaying = false;

      // Only transition to paused if not force stopped
      if (!_audioForceStopped) {
        onStateChange?.call(VoiceState.paused);
        debugPrint('TTS playback complete, file at: $audioPath');
      }

      return audioPath;
    } catch (e) {
      debugPrint('Error generating/playing TTS: $e');
      _audioPlaybackCompleter = null;
      _isPlaying = false;
      return null;
    }
  }

  /// Play audio from a remote URL (for cached report audio)
  Future<void> playAudioFromUrl(String url) async {
    try {
      debugPrint('Playing audio from URL: $url');

      // Reset force stop flag for new playback
      _audioForceStopped = false;

      onStateChange?.call(VoiceState.speaking);

      try { await _player.stop(); } catch (_) {}
      _isPlaying = true;

      final completer = Completer<void>();
      _audioPlaybackCompleter = completer;
      StreamSubscription<void>? subscription;
      subscription = _player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted && !_audioForceStopped) {
          completer.complete();
          subscription?.cancel();
        }
      });

      await _player.play(UrlSource(url));
      await completer.future.timeout(const Duration(seconds: 120), onTimeout: () {
        subscription?.cancel();
      });

      _audioPlaybackCompleter = null;
      _isPlaying = false;

      // Only transition to paused if not force stopped
      if (!_audioForceStopped) {
        onStateChange?.call(VoiceState.paused);
        debugPrint('URL audio playback complete');
      }
    } catch (e) {
      debugPrint('Error playing audio from URL: $e');
      _audioPlaybackCompleter = null;
      _isPlaying = false;
      if (!_audioForceStopped) {
        onStateChange?.call(VoiceState.paused);
      }
      rethrow;
    }
  }

  // Lesson mode listening state
  bool _isLessonListening = false;
  int? _lessonSessionId;
  Timer? _lessonMaxTimer;
  Timer? _lessonSilenceTimer;
  StreamSubscription? _lessonAmplitudeSubscription;
  DateTime? _lessonLastSpeechTime;
  bool _lessonHasDetectedSpeech = false;
  // Note: Max duration is controlled by GameController timer (based on settings)
  // Pipeline only handles silence detection for lesson mode
  static const Duration _lessonSilenceThreshold = Duration(milliseconds: 1500);

  /// Callback for when lesson transcription is complete
  /// Parameters: transcription text, session ID
  void Function(String transcription, int sessionId)? onLessonTranscriptionComplete;

  /// Start listening for lesson mode (self-contained with auto-stop)
  Future<void> startLessonListening({int? sessionId}) async {
    debugPrint('PIPELINE: startLessonListening() called (sessionId=$sessionId)');

    if (_isRecording || _isLessonListening) {
      debugPrint('PIPELINE: startLessonListening EARLY RETURN - already recording');
      return;
    }

    final hasPermission = await checkMicrophonePermission();
    if (!hasPermission) {
      debugPrint('PIPELINE: startLessonListening EARLY RETURN - no permission');
      onError?.call('Microphone permission denied');
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('PIPELINE: startLessonListening EARLY RETURN - recorder no permission');
        onError?.call('Microphone permission denied');
        return;
      }

      _isLessonListening = true;
      _lessonSessionId = sessionId;
      _lessonHasDetectedSpeech = false;
      _lessonLastSpeechTime = null;

      onStateChange?.call(VoiceState.listening);

      final recordingPath = await _getRecordingPath();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: recordingPath,
      );
      _isRecording = true;
      _currentRecordingPath = recordingPath;
      _recordingStartTime = DateTime.now();

      debugPrint('PIPELINE: lesson recording STARTED path=$recordingPath');

      // Note: Max duration timer is handled by GameController (uses settings)
      // Pipeline only monitors for silence detection
      _startLessonAmplitudeMonitoring(recordingPath);

    } catch (e) {
      debugPrint('PIPELINE: startLessonListening FAILED: $e');
      _isLessonListening = false;
      onError?.call('Failed to start recording');
    }
  }

  /// Amplitude monitoring specifically for lesson mode
  void _startLessonAmplitudeMonitoring(String recordingPath) {
    _lessonAmplitudeSubscription?.cancel();
    _lessonAmplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      if (!_isLessonListening || !_isRecording) return;

      final db = amp.current;

      // Speech detection (same threshold as chat mode)
      if (db > _speechAmplitudeThreshold) {
        _lessonHasDetectedSpeech = true;
        _lessonLastSpeechTime = DateTime.now();
        _lessonSilenceTimer?.cancel();
      } else if (_lessonHasDetectedSpeech && _lessonLastSpeechTime != null) {
        // We've detected speech before, now it's quiet - start silence timer
        final silenceDuration = DateTime.now().difference(_lessonLastSpeechTime!);
        if (silenceDuration >= _lessonSilenceThreshold) {
          debugPrint('PIPELINE: lesson recording SILENCE detected after speech');
          _autoStopLessonListening('silence');
        }
      }
    });
  }

  /// Auto-stop lesson listening and trigger transcription
  Future<void> _autoStopLessonListening(String reason) async {
    if (!_isLessonListening) {
      debugPrint('PIPELINE: _autoStopLessonListening called but not lesson listening');
      return;
    }

    debugPrint('PIPELINE: lesson recording AUTO-STOP (reason=$reason)');

    // Cancel timers and subscriptions
    _lessonMaxTimer?.cancel();
    _lessonSilenceTimer?.cancel();
    _lessonAmplitudeSubscription?.cancel();

    final sessionId = _lessonSessionId ?? 0;
    _isLessonListening = false;

    if (!_isRecording) {
      debugPrint('PIPELINE: lesson mic STOPPED (not recording)');
      return;
    }

    try {
      _isRecording = false;
      final path = await _recorder.stop();
      _currentRecordingPath = null;

      debugPrint('PIPELINE: lesson mic STOPPED path=$path');

      if (path == null) {
        debugPrint('PIPELINE: no recording path, skipping transcription');
        return;
      }

      // Transcribe
      debugPrint('PIPELINE: lesson transcription START');
      onStateChange?.call(VoiceState.processing);
      final transcription = await _speechToText(path);
      debugPrint('PIPELINE: lesson transcription DONE text="${transcription ?? ""}"');

      // Call the lesson transcription callback
      if (transcription != null && transcription.isNotEmpty) {
        debugPrint('PIPELINE: calling onLessonTranscriptionComplete(sessionId=$sessionId)');
        onLessonTranscriptionComplete?.call(transcription, sessionId);
      } else {
        debugPrint('PIPELINE: empty transcription, not calling callback');
      }

    } catch (e) {
      debugPrint('PIPELINE: lesson auto-stop FAILED: $e');
      _isRecording = false;
    }
  }

  /// Stop lesson listening manually (cancels auto-stop)
  Future<String?> stopLessonListening() async {
    debugPrint('PIPELINE: stopLessonListening() called (manual)');

    // Cancel auto-stop mechanisms
    _lessonMaxTimer?.cancel();
    _lessonSilenceTimer?.cancel();
    _lessonAmplitudeSubscription?.cancel();
    _isLessonListening = false;

    if (!_isRecording) {
      debugPrint('PIPELINE: stopLessonListening EARLY RETURN - not recording');
      return null;
    }

    try {
      _isRecording = false;
      final path = await _recorder.stop();
      _currentRecordingPath = null;

      debugPrint('PIPELINE: lesson mic STOPPED (manual), path=$path');

      if (path == null) return null;

      // Transcribe
      onStateChange?.call(VoiceState.processing);
      final transcription = await _speechToText(path);
      debugPrint('PIPELINE: lesson transcription result: "$transcription"');
      return transcription;
    } catch (e) {
      debugPrint('PIPELINE: stopLessonListening FAILED: $e');
      _isRecording = false;
      return null;
    }
  }
  
  /// Transcribe audio to text (for ChatPage record-to-text feature)
  Future<String?> transcribeAudio(String audioPath) async {
    return await _speechToText(audioPath);
  }
  
  /// Record audio for transcription (returns path to audio file)
  Future<String?> startTranscriptionRecording() async {
    final hasPermission = await checkMicrophonePermission();
    if (!hasPermission) {
      return null;
    }
    
    try {
      final tempDir = await getTemporaryDirectory();
      final audioPath = '${tempDir.path}/chat_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: audioPath,
      );
      
      _currentRecordingPath = audioPath;
      _recordingStartTime = DateTime.now();
      debugPrint('Started transcription recording: $audioPath');
      
      return audioPath;
    } catch (e) {
      debugPrint('Error starting transcription recording: $e');
      return null;
    }
  }
  
  /// Stop transcription recording and return the audio path
  Future<String?> stopTranscriptionRecording() async {
    try {
      final path = await _recorder.stop();
      debugPrint('Stopped transcription recording: $path');
      _currentRecordingPath = null;
      return path;
    } catch (e) {
      debugPrint('Error stopping transcription recording: $e');
      return null;
    }
  }

  /// Build enhanced system prompt to ensure stable conversation
  String _buildSystemPrompt(String personalityPrompt) {
    final baseInstructions = '''You are having a continuous conversation with a user.
- Keep responses concise and conversational (2-3 sentences max).
- Do NOT say goodbye, farewell, or end the conversation unless the user explicitly asks to end it.
- Continue the conversation naturally and wait for the user's next question or statement.
- Stay in character and maintain the conversation flow.
- Do not make up information you don't know - say "I don't know" if unsure.

NOTES CAPABILITY:
You can create, read, update, and manage notes for the user. Use notes to:
- Save recipes, shopping lists, or procedures the user wants to keep
- Create structured content they can reference later (ingredients, steps, lists)
- Update notes in real-time as the conversation progresses
- Keep important information separate from the chat for permanent reference

When the user discusses something they might want to save (like a recipe, shopping list, or instructions),
offer to create a note for them. When a note is open/active, you can update or append to it as needed.
Format note content nicely with line breaks, bullet points, and clear sections.

''';
    
    // Build user context section
    String userContext = '';
    if (_currentUsername != null && _currentUsername!.isNotEmpty) {
      userContext += '\nUser Information:\n- Username: ${_currentUsername}';
    }
    if (_currentBio != null && _currentBio!.isNotEmpty) {
      userContext += '\n- Bio: ${_currentBio}';
    }
    
    // Combine personality, user context, and instructions
    String systemPrompt = '';
    if (personalityPrompt.isNotEmpty) {
      systemPrompt = personalityPrompt;
      if (userContext.isNotEmpty) {
        systemPrompt += userContext;
      }
      systemPrompt += '\n\n$baseInstructions';
    } else {
      if (userContext.isNotEmpty) {
        systemPrompt = userContext + '\n\n$baseInstructions';
      } else {
        systemPrompt = baseInstructions;
      }
    }
    
    return systemPrompt;
  }

  Future<String?> _speechToText(String audioPath) async {
    debugPrint('STT processing: $audioPath');
    
    try {
      // Use OpenAI Whisper API
      final transcription = await _openaiService.speechToText(audioPath);
      
      if (transcription != null && transcription.isNotEmpty) {
        debugPrint('Transcription received: $transcription');
        return transcription;
      }
      
      debugPrint('No transcription received');
      return null;
    } catch (e) {
      debugPrint('STT error: $e');
      return null;
    }
  }

  Future<String?> _callLLM({
    required String transcription,
    required String personalityPrompt,
    required List<Map<String, dynamic>> conversationHistory,
  }) async {
    debugPrint('LLM processing: $transcription');

    try {
      // Use IntentRouter to detect intent (used for both tools AND instructions)
      // This significantly reduces token usage (60-90% savings on instructions)
      Set<IntentCategory> intents = {IntentCategory.none};
      if (noteToolsHandler != null) {
        intents = IntentRouter.detectIntent(transcription);

        // Merge with forced intents (e.g., reports tools when on Reports page)
        if (noteToolsHandler!.forcedIntents.isNotEmpty) {
          intents = {...intents, ...noteToolsHandler!.forcedIntents};
          intents.remove(IntentCategory.none); // Remove 'none' if we have real intents
          debugPrint('IntentRouter: Merged forced intents: ${noteToolsHandler!.forcedIntents}');
        }
      }

      // Build enhanced system prompt with intent-aware context
      String enhancedPrompt = personalityPrompt;
      if (noteToolsHandler != null) {
        enhancedPrompt += noteToolsHandler!.getActiveNoteContext(intents: intents);
      }

      // Get only relevant tools based on detected intents
      List<Map<String, dynamic>>? tools;
      if (noteToolsHandler != null) {
        final toolNames = IntentRouter.getToolNamesForCategories(intents);

        if (toolNames.isNotEmpty) {
          tools = NoteToolsHandler.getToolsByNames(toolNames);
          // Always add request_capability as fallback
          tools.add(NoteToolsHandler.requestCapabilityTool);
          debugPrint('IntentRouter: Sending ${tools.length} tools for intents: $intents');
        } else {
          // Even for conversation-only, include request_capability as escape hatch
          tools = [NoteToolsHandler.requestCapabilityTool];
          debugPrint('IntentRouter: Conversation only - just request_capability tool');
        }
      }

      // Check if alternative LLM handler is set (e.g., OpenClaw for conversation mode)
      // Note: OpenClaw/Bubble has its own skills configured server-side
      // Tools and system prompts are passed for API compatibility but may be ignored
      if (alternativeLLMHandler != null) {
        debugPrint('Using alternative LLM handler (OpenClaw)');
        final alternativeResponse = await alternativeLLMHandler!(
          userMessage: transcription,
          systemPrompt: enhancedPrompt,
          tools: tools,
          conversationHistory: conversationHistory,
        );
        if (alternativeResponse != null) {
          debugPrint('Alternative LLM response: ${alternativeResponse.substring(0, alternativeResponse.length > 50 ? 50 : alternativeResponse.length)}...');
          return alternativeResponse;
        }
        // If alternative returns null, fall through to default LLM
        debugPrint('Alternative LLM returned null, falling back to default');
      }

      // Use OpenAI Chat Completions API with tools
      var response = await _openaiService.callChatCompletions(
        systemPrompt: enhancedPrompt,
        conversationHistory: conversationHistory,
        userMessage: transcription,
        model: 'gpt-4o-mini', // Using cheaper model, can upgrade to gpt-4 if needed
        tools: tools,
      );
      
      if (response == null) {
        debugPrint('LLM returned null response');
        return null;
      }
      
      // Track total tokens across all calls (including tool calls)
      int totalTokensUsed = response.totalTokens;
      
      // Handle tool calls if the AI wants to use tools
      if (response.hasToolCalls && noteToolsHandler != null) {
        response = await _handleToolCalls(
          response: response,
          conversationHistory: conversationHistory,
          userMessage: transcription,
          systemPrompt: enhancedPrompt,
          tools: tools,
          totalTokensUsed: totalTokensUsed,
        );
        
        if (response == null) {
          return null;
        }
        
        // Update total tokens
        totalTokensUsed += response.totalTokens;
      }
      
      if (response.content.isNotEmpty) {
        debugPrint('LLM response received: ${response.content.substring(0, response.content.length > 50 ? 50 : response.content.length)}...');
        
        // Record token usage after successful call (for tracking, not blocking)
        if (_currentUserId != null && 
            _currentUserEmail != null && 
            _currentSubscriptionStatus != null &&
            _currentSubscriptionStatus!.isUsable) {
          
          try {
            debugPrint('Recording usage: userId=${_currentUserId}, email=${_currentUserEmail}, status=${_currentSubscriptionStatus}, tokens=$totalTokensUsed');
            await UsageTrackingService.recordUsage(
              userId: _currentUserId!,
              userEmail: _currentUserEmail!,
              subscriptionStatus: _currentSubscriptionStatus!,
              tokensUsed: totalTokensUsed,
            );
            debugPrint('✓ Token usage recorded: $totalTokensUsed tokens');
          } catch (e) {
            debugPrint('Error recording usage (non-fatal): $e');
            // Don't fail the call if usage recording fails
          }
        } else {
          debugPrint('⚠ Usage NOT recorded - userId: $_currentUserId, email: $_currentUserEmail, status: $_currentSubscriptionStatus, isUsable: ${_currentSubscriptionStatus?.isUsable}');
        }
        
        return response.content;
      }
      
      debugPrint('LLM returned empty response');
      return null;
    } catch (e) {
      debugPrint('LLM error: $e');
      return null;
    }
  }
  
  /// Handle tool calls from the AI
  /// [depth] limits recursion to prevent infinite loops
  Future<ChatCompletionResponse?> _handleToolCalls({
    required ChatCompletionResponse response,
    required List<Map<String, dynamic>> conversationHistory,
    required String userMessage,
    required String systemPrompt,
    required List<Map<String, dynamic>>? tools,
    required int totalTokensUsed,
    int depth = 0,
  }) async {
    const maxDepth = 5; // Prevent infinite tool call loops
    
    if (!response.hasToolCalls || noteToolsHandler == null) {
      return response;
    }
    
    if (depth >= maxDepth) {
      debugPrint('WARNING: Max tool call depth ($maxDepth) reached, stopping recursion');
      return response;
    }
    
    debugPrint('Handling ${response.toolCalls!.length} tool call(s) at depth $depth');
    
    // Build updated conversation history with tool calls and results
    final updatedHistory = List<Map<String, dynamic>>.from(conversationHistory);
    
    // Add user message
    updatedHistory.add({
      'role': 'user',
      'content': userMessage,
    });
    
    // Add assistant message with tool calls
    updatedHistory.add({
      'role': 'assistant',
      'content': response.content,
      'tool_calls': response.toolCalls!.map((tc) => {
        'id': tc.id,
        'type': 'function',
        'function': {
          'name': tc.name,
          'arguments': jsonEncode(tc.arguments),
        },
      }).toList(),
    });
    
    // Execute each tool call and add results
    String? requestedCapability;
    for (final toolCall in response.toolCalls!) {
      debugPrint('Executing tool: ${toolCall.name}');

      final result = await noteToolsHandler!.executeTool(toolCall);

      // Check if this is a capability request (needs retry with expanded tools)
      if (result.requestedCapability != null) {
        requestedCapability = result.requestedCapability;
        debugPrint('Capability requested: $requestedCapability - will retry with expanded tools');
      }

      // Add tool result to history
      updatedHistory.add({
        'role': 'tool',
        'tool_call_id': toolCall.id,
        'content': jsonEncode(result.toJson()),
      });

      debugPrint('Tool ${toolCall.name} result: ${result.success ? "success" : "failed"} - ${result.message}');
    }

    // If capability was requested, rebuild prompt and tools with the requested capability
    String effectiveSystemPrompt = systemPrompt;
    List<Map<String, dynamic>>? effectiveTools = tools;

    if (requestedCapability != null && noteToolsHandler != null) {
      // Map capability string to IntentCategory
      final capabilityIntent = _mapCapabilityToIntent(requestedCapability);
      if (capabilityIntent != null) {
        debugPrint('Expanding tools/instructions for capability: $capabilityIntent');

        // Get tools for this capability
        final capabilityToolNames = IntentRouter.getToolNamesForCategories({capabilityIntent});
        final capabilityTools = NoteToolsHandler.getToolsByNames(capabilityToolNames);

        // Merge with existing tools (avoid duplicates)
        final existingToolNames = (tools ?? []).map((t) =>
          (t['function'] as Map<String, dynamic>?)?['name'] as String?
        ).whereType<String>().toSet();

        effectiveTools = [...(tools ?? [])];
        for (final tool in capabilityTools) {
          final toolName = (tool['function'] as Map<String, dynamic>?)?['name'];
          if (toolName != null && !existingToolNames.contains(toolName)) {
            effectiveTools.add(tool);
          }
        }

        // Rebuild system prompt with the requested capability's instructions
        // We append the new instructions to the existing prompt
        effectiveSystemPrompt = systemPrompt + noteToolsHandler!.getActiveNoteContext(intents: {capabilityIntent});

        debugPrint('Expanded to ${effectiveTools.length} tools with $capabilityIntent instructions');
      }
    }

    // Continue conversation with tool results
    final continuedResponse = await _openaiService.continueWithToolResults(
      systemPrompt: effectiveSystemPrompt,
      conversationHistory: updatedHistory,
      model: 'gpt-4o-mini',
      tools: effectiveTools,
    );
    
    if (continuedResponse == null) {
      debugPrint('Failed to continue conversation after tool calls');
      return null;
    }
    
    // If there are more tool calls, handle them recursively (with depth limit)
    if (continuedResponse.hasToolCalls) {
      debugPrint('AI requested more tool calls, handling recursively (depth ${depth + 1})');
      return await _handleToolCalls(
        response: continuedResponse,
        conversationHistory: updatedHistory,
        userMessage: '', // Already in history
        systemPrompt: effectiveSystemPrompt,
        tools: effectiveTools,
        totalTokensUsed: totalTokensUsed + continuedResponse.totalTokens,
        depth: depth + 1,
      );
    }

    return continuedResponse;
  }

  /// Map capability string to IntentCategory
  IntentCategory? _mapCapabilityToIntent(String capability) {
    switch (capability.toLowerCase()) {
      case 'notes':
        return IntentCategory.notes;
      case 'schedule':
        return IntentCategory.schedule;
      case 'weather':
        return IntentCategory.weather;
      case 'apps':
        return IntentCategory.apps;
      case 'games':
        return IntentCategory.games;
      case 'navigation':
        return IntentCategory.navigation;
      default:
        debugPrint('Unknown capability requested: $capability');
        return null;
    }
  }

  Future<String?> _textToSpeech(String text, String voice) async {
    // Sanitize text for better TTS pronunciation
    String sanitizedText = text
        .replaceAll('°F', ' degrees')
        .replaceAll('°C', ' degrees')
        .replaceAll('°', ' degrees')
        .replaceAll('℉', ' degrees')
        .replaceAll('℃', ' degrees');

    debugPrint('TTS processing: $sanitizedText with voice: $voice');

    try {
      // Use OpenAI TTS API
      final audioPath = await _openaiService.textToSpeech(
        text: sanitizedText,
        voice: voice,
        model: 'tts-1', // Can use 'tts-1-hd' for higher quality
      );
      
      if (audioPath != null && audioPath.isNotEmpty) {
        debugPrint('TTS audio generated: $audioPath');
        return audioPath;
      }
      
      debugPrint('TTS returned empty audio path');
      return null;
    } catch (e) {
      debugPrint('TTS error: $e');
      return null;
    }
  }

  /// Split text into sentence chunks for parallel TTS generation
  List<String> _splitIntoChunks(String text) {
    if (text.trim().isEmpty) return [];
    
    // Split by sentence boundaries (., !, ?) followed by space or end
    // Use regex to split on sentence endings while preserving the punctuation
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    
    // Filter out empty strings and trim whitespace
    final chunks = sentences
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    
    // If no sentence breaks found, return the whole text as one chunk
    if (chunks.isEmpty) {
      return [text.trim()];
    }
    
    // Combine very short chunks (less than 20 chars) with next chunk to avoid too many small requests
    final List<String> combinedChunks = [];
    String currentChunk = '';
    
    for (final chunk in chunks) {
      if (currentChunk.isEmpty) {
        currentChunk = chunk;
      } else if (currentChunk.length < 20 && chunk.length < 20) {
        // Combine small chunks
        currentChunk = '$currentChunk $chunk';
      } else {
        // Add current chunk and start new one
        combinedChunks.add(currentChunk);
        currentChunk = chunk;
      }
    }
    
    // Add the last chunk
    if (currentChunk.isNotEmpty) {
      combinedChunks.add(currentChunk);
    }
    
    debugPrint('Split text into ${combinedChunks.length} chunks');
    return combinedChunks;
  }

  /// Generate TTS audio for multiple text chunks in parallel
  Future<List<String>> _generateTTSChunks(String text, String voice) async {
    final chunks = _splitIntoChunks(text);
    
    if (chunks.isEmpty) {
      debugPrint('No chunks to generate TTS for');
      return [];
    }
    
    debugPrint('Generating TTS for ${chunks.length} chunks in parallel...');
    
    // Generate TTS for all chunks in parallel
    final futures = chunks.map((chunk) => _textToSpeech(chunk, voice));
    final results = await Future.wait(futures);
    
    // Filter out null results and return list of audio file paths
    final audioChunks = results.whereType<String>().toList();
    
    debugPrint('Generated ${audioChunks.length}/${chunks.length} TTS chunks');
    return audioChunks;
  }

  /// Play multiple audio chunks sequentially
  /// If forcePlay is true, audio will play even when paused (used for AI navigation responses)
  Future<void> _playAudioChunks(List<String> audioChunks, {bool autoResumeListening = false, bool forcePlay = false}) async {
    if (audioChunks.isEmpty) {
      debugPrint('No audio chunks to play');
      if (autoResumeListening && _isContinuousMode && !_isPaused) {
        await startListening(
          continuousMode: true,
          agentId: _currentAgentId,
          personalityPrompt: _currentPersonalityPrompt,
          aiServiceId: _currentAiServiceId,
          voice: _currentVoice,
          username: _currentUsername,
          bio: _currentBio,
          userId: _currentUserId,
          userEmail: _currentUserEmail,
          subscriptionStatus: _currentSubscriptionStatus,
          getConversationHistory: _getConversationHistory,
        );
      }
      return;
    }
    
    onStateChange?.call(VoiceState.speaking);
    _isPlaying = true;
    
    try {
      // Play each chunk sequentially
      for (int i = 0; i < audioChunks.length; i++) {
        // Stop if continuous mode was disabled (session ended)
        if (!_isContinuousMode) break;
        // Allow force play to override pause check (for AI tool responses)
        if (_isPaused && !forcePlay) break; // Stop playing if paused (unless forced)

        final audioPath = audioChunks[i];
        debugPrint('Playing audio chunk ${i + 1}/${audioChunks.length}');
        
        final completer = Completer<void>();
        StreamSubscription<void>? subscription;
        subscription = _player.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) {
            completer.complete();
            subscription?.cancel();
          }
        });
        
        await _player.play(DeviceFileSource(audioPath));
        await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
          subscription?.cancel();
        });
      }
      
      debugPrint('Finished playing all ${audioChunks.length} audio chunks');
    } catch (e) {
      debugPrint('Failed to play audio chunks: $e');
    } finally {
      _isPlaying = false;

      // Wait a moment after audio finishes before transitioning
      await Future.delayed(const Duration(milliseconds: 500));

      // Fire TTS completion callback for lesson mode FSM
      onTTSPlaybackComplete?.call();

      // Check if AI requested a pause (e.g., user said "pause")
      if (noteToolsHandler != null && noteToolsHandler!.checkAndClearPauseFlag()) {
        debugPrint('AI requested pause after response - pausing now');
        await pauseContinuousMode();
        onStateChange?.call(VoiceState.paused);
        return;
      }

      // Execute any pending navigation (after TTS completes to avoid breaking audio)
      noteToolsHandler?.checkAndExecutePendingNavigation();

      // Resume listening if auto-resume is enabled (normal conversation mode)
      // Only resume if still in continuous mode (session not ended)
      if (autoResumeListening && _isContinuousMode && !_isPaused) {
        debugPrint('Audio finished - resuming listening in conversation mode');
        onStateChange?.call(VoiceState.listening);
        await startListening(
          continuousMode: true,
          agentId: _currentAgentId,
          personalityPrompt: _currentPersonalityPrompt,
          aiServiceId: _currentAiServiceId,
          voice: _currentVoice,
          username: _currentUsername,
          bio: _currentBio,
          userId: _currentUserId,
          userEmail: _currentUserEmail,
          subscriptionStatus: _currentSubscriptionStatus,
          getConversationHistory: _getConversationHistory,
        );
      } else if (_isContinuousMode && !_isPaused) {
        onStateChange?.call(VoiceState.listening);
      }
    }
  }

  Future<void> _playAudio(String audioPath, {bool autoResumeListening = false}) async {
    // Don't play if paused AND we're in an active continuous session
    // But allow playback if it's a fresh start (not yet in continuous mode)
    if (_isPaused && _isContinuousMode && _isPlaying == false) {
      debugPrint('Skipping audio playback - system is paused in active session');
      return;
    }
    
    debugPrint('Starting audio playback: $audioPath (paused: $_isPaused, continuous: $_isContinuousMode, playing: $_isPlaying)');
    
    // Ensure player is in clean state
    try {
      await _player.stop();
    } catch (e) {
      // Ignore - player might not be playing
    }
    
    onStateChange?.call(VoiceState.speaking);
    _isPlaying = true;
    
    try {
      debugPrint('Attempting to play audio file: $audioPath');
      
      // Verify file exists before playing
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        debugPrint('ERROR: Audio file does not exist: $audioPath');
        onError?.call('Audio file not found');
        return;
      }
      
      debugPrint('Playing audio file (${await audioFile.length()} bytes)');
      
      // Use a Completer for more reliable completion detection
      final completer = Completer<void>();
      StreamSubscription<void>? subscription;
      
      subscription = _player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) {
          completer.complete();
          subscription?.cancel();
        }
      });
      
      await _player.play(DeviceFileSource(audioPath));
      debugPrint('Audio playback started, waiting for completion...');
      
      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('Audio playback timed out');
          subscription?.cancel();
        },
      );
      debugPrint('Audio playback completed');
    } catch (e, stackTrace) {
      debugPrint('Failed to play audio: $e');
      debugPrint('Stack trace: $stackTrace');
      onError?.call('Failed to play audio: $e');
    } finally {
      _isPlaying = false;

      // Wait a moment after audio finishes before starting listening (prevents interruptions)
      await Future.delayed(const Duration(milliseconds: 500));

      // Fire TTS completion callback for lesson mode FSM
      onTTSPlaybackComplete?.call();

      // Resume listening if not paused
      if (!_isPaused && autoResumeListening && _isContinuousMode) {
        await startListening(
          continuousMode: true,
          agentId: _currentAgentId,
          personalityPrompt: _currentPersonalityPrompt,
          aiServiceId: _currentAiServiceId,
          voice: _currentVoice,
          username: _currentUsername,
          bio: _currentBio,
          userId: _currentUserId,
          userEmail: _currentUserEmail,
          subscriptionStatus: _currentSubscriptionStatus,
          getConversationHistory: _getConversationHistory,
        );
      } else if (!_isPaused) {
        onStateChange?.call(VoiceState.listening);
      }
    }
  }

  /// Play an intro message (TTS + Audio playback), then auto-start listening
  Future<void> playIntroMessage(
    String introText,
    String voice, {
    bool autoStartListening = false,
    String? agentId,
    String? personalityPrompt,
    String? aiServiceId,
    String? username,
    String? bio,
    String? userId,
    String? userEmail,
    AIServiceStatus? subscriptionStatus,
    Function()? getConversationHistory,
  }) async {
    try {
      debugPrint('Playing intro message: $introText');
      debugPrint('Current state - paused: $_isPaused, playing: $_isPlaying, recording: $_isRecording');

      // Check if paused - don't override user's pause
      if (_isPaused) {
        debugPrint('Intro message skipped - session is paused');
        return;
      }

      // Reset force stop flag for new playback
      _audioForceStopped = false;

      // Generate TTS audio
      final audioPath = await _textToSpeech(introText, voice);

      // Check if paused or force stopped during TTS generation
      if (_isPaused || _audioForceStopped) {
        debugPrint('Intro message aborted - paused or force stopped during TTS generation');
        return;
      }

      if (audioPath == null || audioPath.isEmpty) {
        debugPrint('Failed to generate intro audio');
        // Still start listening if auto-start is enabled and not paused
        if (autoStartListening && !_isPaused) {
          await startListening(
            continuousMode: true,
            agentId: agentId,
            personalityPrompt: personalityPrompt,
            aiServiceId: aiServiceId,
            voice: voice,
            username: username,
            bio: bio,
            userId: userId,
            userEmail: userEmail,
            subscriptionStatus: subscriptionStatus,
            getConversationHistory: getConversationHistory,
          );
        }
        return;
      }

      // Verify file exists
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        debugPrint('ERROR: Audio file does not exist: $audioPath');
        onError?.call('Audio file not found');
        return;
      }
      debugPrint('Audio file exists: $audioPath, size: ${await audioFile.length()} bytes');

      // Store context for continuous mode if auto-starting
      if (autoStartListening) {
        _isContinuousMode = true;
        _currentAgentId = agentId;
        _currentPersonalityPrompt = personalityPrompt;
        _currentAiServiceId = aiServiceId;
        _currentVoice = voice;
        _currentUsername = username;
        _currentBio = bio;
        _currentUserId = userId;
        _currentUserEmail = userEmail;
        _currentSubscriptionStatus = subscriptionStatus;
        _getConversationHistory = getConversationHistory;
      }

      // Final check before playing
      if (_isPaused || _audioForceStopped) {
        debugPrint('Intro message aborted - paused or force stopped before playback');
        return;
      }

      // Ensure player is in clean state before playing
      try {
        await _player.stop();
      } catch (e) {
        // Ignore - player might not be playing
      }
      _isPlaying = false;

      debugPrint('Starting intro audio playback: $audioPath');
      onStateChange?.call(VoiceState.speaking);
      _isPlaying = true;

      try {
        // Use a Completer for reliable completion detection
        final completer = Completer<void>();
        _audioPlaybackCompleter = completer;
        StreamSubscription<void>? subscription;

        subscription = _player.onPlayerComplete.listen((_) {
          if (!completer.isCompleted && !_audioForceStopped) {
            completer.complete();
            subscription?.cancel();
          }
        });

        await _player.play(DeviceFileSource(audioPath));
        debugPrint('Intro audio playback started, waiting for completion...');

        // Wait for completion with timeout
        await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('Intro audio playback timed out');
            subscription?.cancel();
          },
        );

        _audioPlaybackCompleter = null;

        // Check if force stopped during playback
        if (_audioForceStopped) {
          debugPrint('Intro audio was force stopped');
          return;
        }

        debugPrint('Intro audio playback completed');
      } catch (e, stackTrace) {
        debugPrint('Failed to play intro audio: $e');
        debugPrint('Stack trace: $stackTrace');
        _audioPlaybackCompleter = null;
        onError?.call('Failed to play intro: $e');
      } finally {
        _isPlaying = false;
        _audioPlaybackCompleter = null;

        // Don't continue if paused, force stopped, or session ended
        if (_isPaused || _audioForceStopped || !_isContinuousMode) {
          debugPrint('Intro audio: Not starting listening (paused: $_isPaused, forceStopped: $_audioForceStopped, continuous: $_isContinuousMode)');
          return;
        }

        // Wait a moment after audio finishes before starting listening
        await Future.delayed(const Duration(milliseconds: 300));

        // Final check before starting listening
        if (_isPaused || _audioForceStopped || !_isContinuousMode) {
          debugPrint('Intro audio: Session state changed during delay, not starting listening');
          return;
        }

        // Auto-start listening if enabled
        if (autoStartListening) {
          await startListening(
            continuousMode: true,
            agentId: agentId,
            personalityPrompt: personalityPrompt,
            aiServiceId: aiServiceId,
            voice: voice,
            username: username,
            bio: bio,
            userId: userId,
            userEmail: userEmail,
            subscriptionStatus: subscriptionStatus,
            getConversationHistory: getConversationHistory,
          );
        } else {
          onStateChange?.call(VoiceState.listening);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error playing intro message: $e');
      debugPrint('Stack trace: $stackTrace');
      onError?.call('Failed to play intro: $e');

      // Don't continue if paused or session ended
      if (_isPaused || !_isContinuousMode) {
        return;
      }

      // Still try to start listening if auto-start is enabled
      if (autoStartListening) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (_isPaused || !_isContinuousMode) return;
        await startListening(
          continuousMode: true,
          agentId: agentId,
          personalityPrompt: personalityPrompt,
          aiServiceId: aiServiceId,
          voice: voice,
          username: username,
          bio: bio,
          userId: userId,
          userEmail: userEmail,
          subscriptionStatus: subscriptionStatus,
          getConversationHistory: getConversationHistory,
        );
      }
    }
  }
  
  /// Simulate speaking for demo purposes (when TTS is not yet implemented)
  Future<void> simulateSpeaking({
    required String text,
    required Duration duration,
  }) async {
    onStateChange?.call(VoiceState.speaking);
    _isPlaying = true;
    
    await Future.delayed(duration);
    
    _isPlaying = false;
    onStateChange?.call(VoiceState.listening);
  }

  Future<String> _getRecordingPath() async {
    try {
      final directory = await getTemporaryDirectory();
      return '${directory.path}/millie_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    } catch (e) {
      debugPrint('Error getting recording path: $e');
      // Fallback path
      return '/tmp/millie_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    }
  }

  void dispose() {
    // Stop recording immediately (can't await in dispose, but we cancel timers first)
    _amplitudeSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordingTimer?.cancel();
    stopContinuousMode(); // Fire and forget async call
    _wakeWordService.dispose(); // Clean up OpenAI Realtime API
    _recorder.dispose();
    _player.dispose();
  }
}

/// Wake Word Detection Service using OpenAI Realtime API
/// Uses OpenAI's Realtime API for cost-effective wake word detection
/// Audio format: 16kHz, mono, 16-bit PCM, little-endian, base64-encoded chunks
class WakeWordService {
  final OpenAIService _openaiService;
  IOWebSocketChannel? _channel;
  AudioRecorder? _recorder;
  StreamSubscription? _audioStream;
  Timer? _audioStreamTimer;
  Timer? _audioCommitTimer;
  bool _isListening = false;
  Function()? onWakeWordDetected;
  
  // Audio format requirements for OpenAI Realtime API
  static const int sampleRate = 16000; // 16kHz
  static const int channels = 1; // mono
  static const int bitsPerSample = 16; // 16-bit
  static const String wakeWord = 'Hey Millie';
  
  WakeWordService(this._openaiService);

  bool get isListening => _isListening;

  /// Start OpenAI Realtime API wake word detection
  /// Uses OpenAI's Realtime API for cost-effective wake word detection
  Future<bool> start() async {
    if (_isListening) return true;
    
    try {
      // Get OpenAI API key
      final apiKey = await _openaiService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('WakeWordService: OpenAI API key not found');
        return false;
      }
      
      // Check microphone permission
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          debugPrint('WakeWordService: Microphone permission denied');
          return false;
        }
      }
      
      // Connect to OpenAI Realtime API WebSocket with authentication
      // Note: OpenAI Realtime API requires Bearer token authentication
      // The web_socket_channel package doesn't directly support headers,
      // so we'll use IOWebSocketChannel with a custom client
      final wsUrl = Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17');
      
      // Create WebSocket connection with authorization header
      // Using IOWebSocketChannel for header support
      final ws = await WebSocket.connect(
        wsUrl.toString(),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
      );
      
      _channel = IOWebSocketChannel(ws);
      
      // Wait for connection to be established
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Configure session for wake word detection only (no STT/LLM to avoid tokens)
      await _configureSession();
      
      // Start listening for WebSocket messages first
      _channel!.stream.listen(
        _handleWebSocketMessage,
        onError: (error) {
          debugPrint('WakeWordService: WebSocket error: $error');
          _isListening = false;
        },
        onDone: () {
          debugPrint('WakeWordService: WebSocket connection closed');
          _isListening = false;
        },
        cancelOnError: false,
      );
      
      // Start recording and streaming audio to WebSocket
      await _startAudioStreaming();
      
      _isListening = true;
      debugPrint('WakeWordService: OpenAI Realtime API wake word detection started (idle mode - wake word only, no tokens)');
      return true;
    } catch (e) {
      debugPrint('WakeWordService: Error starting wake word detection: $e');
      _isListening = false;
      await stop();
      return false;
    }
  }
  
  /// Configure the Realtime API session for wake word detection only
  /// STT and LLM are disabled to avoid token usage during idle mode
  Future<void> _configureSession() async {
    // According to OpenAI Realtime API, wake word config goes inside session
    final config = {
      'type': 'session.update',
      'session': {
        'modalities': ['audio', 'text'],
        'input_audio_format': 'pcm16',
        'input_audio_transcription': {
          'enabled': false, // Disable STT to avoid token usage
        },
        'turn_detection': {
          'type': 'none', // No turn detection needed for wake word only
        },
        // Wake word detection configuration
        'enable_wakeword_detection': true,
        'wakewords': [wakeWord],
      },
    };
    
    _channel?.sink.add(jsonEncode(config));
    debugPrint('WakeWordService: Session configured for wake word detection (STT/LLM disabled, wakeword: $wakeWord)');
    
    // Wait for session configured event
    await Future.delayed(const Duration(milliseconds: 500));
  }
  
  /// Handle incoming WebSocket messages
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final eventType = data['type'] as String?;
      
      if (eventType == null) return;
      
      debugPrint('WakeWordService: Received event: $eventType');
      
      // Handle wake word detection event (exact format from OpenAI Realtime API)
      if (eventType == 'input_audio.wakeword_detected') {
        final keyword = data['keyword'] as String?;
        final timestamp = data['timestamp'];
        debugPrint('WakeWordService: Wake word "$keyword" detected at timestamp: $timestamp');
        if (keyword != null && keyword.toLowerCase() == wakeWord.toLowerCase()) {
          onWakeWordDetected?.call();
        }
      }
      
      // Handle session updated event
      if (eventType == 'session.updated') {
        debugPrint('WakeWordService: Session updated successfully');
      }
      
      // Handle errors
      if (eventType == 'error') {
        final error = data['error'];
        debugPrint('WakeWordService: API error: $error');
      }
    } catch (e) {
      debugPrint('WakeWordService: Error parsing WebSocket message: $e');
      debugPrint('WakeWordService: Raw message: $message');
    }
  }
  
  /// Start streaming audio from microphone to WebSocket
  /// Streams PCM16 audio in base64-encoded chunks continuously
  /// Audio format: 16kHz, mono, 16-bit PCM, little-endian
  Future<void> _startAudioStreaming() async {
    _recorder = AudioRecorder();
    
    try {
      // Get temporary recording path for continuous recording
      final recordingPath = await _getRecordingPath();
      
      // Start recording with 16kHz, mono configuration
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: channels,
        ),
        path: recordingPath,
      );
      
      debugPrint('WakeWordService: Recording started at $sampleRate Hz, $channels channel(s)');
      debugPrint('WakeWordService: Starting continuous audio streaming to OpenAI Realtime API');
      
      // Parse WAV header to find PCM data start position
      int pcmDataStart = 0;
      bool headerParsed = false;
      int lastFileSize = 0;
      
      // Buffer to accumulate PCM data between sends
      final List<int> pcmBuffer = [];
      // Target chunk size: 250ms = 4000 samples = 8000 bytes (16-bit mono at 16kHz)
      const int targetChunkSize = (sampleRate * bitsPerSample ~/ 8 * channels) ~/ 4; // 250ms
      // Minimum audio for commit: 100ms = 1600 samples = 3200 bytes
      const int minAudioForCommit = (sampleRate * bitsPerSample ~/ 8 * channels) ~/ 10; // 100ms
      
      // Track total bytes sent since last commit
      int bytesSentSinceCommit = 0;
      
      // Stream audio chunks continuously (250ms intervals)
      _audioStreamTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
        if (!_isListening || _channel == null) {
          timer.cancel();
          return;
        }
        
        try {
          final file = File(recordingPath);
          if (await file.exists()) {
            final currentSize = await file.length();
            
            // Parse WAV header on first read
            if (!headerParsed && currentSize >= 44) {
              // Read first 44 bytes (or more) to parse header
              final allBytes = await file.readAsBytes();
              if (allBytes.length >= 44) {
                final headerBytes = allBytes.sublist(0, 44);
                pcmDataStart = _parseWavHeader(headerBytes);
                if (pcmDataStart > 0) {
                  headerParsed = true;
                  lastFileSize = pcmDataStart;
                  debugPrint('WakeWordService: WAV header parsed, PCM data starts at byte $pcmDataStart');
                }
              }
            }
            
            // Only process if header is parsed and we have new data
            if (headerParsed && currentSize > lastFileSize) {
              // Read new bytes (only PCM data, header already skipped)
              final randomAccessFile = await file.open(mode: FileMode.read);
              await randomAccessFile.setPosition(lastFileSize);
              final newBytes = await randomAccessFile.read(currentSize - lastFileSize);
              await randomAccessFile.close();
              
              debugPrint('WakeWordService: Read ${newBytes.length} new bytes from file (file size: $currentSize, last position: $lastFileSize)');
              
              // Add to buffer
              pcmBuffer.addAll(newBytes);
              
              // Send chunks when buffer reaches target size
              int chunksSent = 0;
              while (pcmBuffer.length >= targetChunkSize) {
                final chunk = Uint8List.fromList(pcmBuffer.sublist(0, targetChunkSize));
                pcmBuffer.removeRange(0, targetChunkSize);
                _sendAudioChunk(chunk);
                bytesSentSinceCommit += chunk.length;
                chunksSent++;
                debugPrint('WakeWordService: Sent audio chunk #$chunksSent: ${chunk.length} bytes (total since commit: $bytesSentSinceCommit, buffer remaining: ${pcmBuffer.length})');
              }
              
              if (chunksSent == 0 && newBytes.isNotEmpty) {
                debugPrint('WakeWordService: Buffered ${newBytes.length} bytes (total in buffer: ${pcmBuffer.length}, need $targetChunkSize for chunk)');
              }
              
              lastFileSize = currentSize;
            } else if (!headerParsed) {
              debugPrint('WakeWordService: Waiting for header parsing (file size: $currentSize)');
            } else if (currentSize <= lastFileSize) {
              debugPrint('WakeWordService: No new data (file size: $currentSize, last: $lastFileSize)');
            }
          }
        } catch (e) {
          debugPrint('WakeWordService: Error streaming audio chunk: $e');
        }
      });
      
      // Commit audio buffer periodically (every 2 seconds, but only if we have enough audio)
      // Note: We need to ensure chunks are processed before committing, so we wait a bit after sending
      _audioCommitTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (!_isListening || _channel == null) {
          timer.cancel();
          return;
        }
        
        try {
          // Only commit if we've sent at least 100ms of audio (3200 bytes)
          // Also add a small delay to ensure chunks are processed by OpenAI
          if (bytesSentSinceCommit >= minAudioForCommit) {
            // Small delay to ensure the last chunk is processed
            await Future.delayed(const Duration(milliseconds: 100));
            
            final commitMessage = {
              'type': 'input_audio_buffer.commit',
            };
            _channel?.sink.add(jsonEncode(commitMessage));
            debugPrint('WakeWordService: Audio buffer committed ($bytesSentSinceCommit bytes sent)');
            bytesSentSinceCommit = 0; // Reset counter
          } else {
            debugPrint('WakeWordService: Skipping commit - not enough audio (only $bytesSentSinceCommit bytes, need $minAudioForCommit)');
          }
        } catch (e) {
          debugPrint('WakeWordService: Error committing audio buffer: $e');
        }
      });
      
    } catch (e) {
      debugPrint('WakeWordService: Error starting audio streaming: $e');
      rethrow;
    }
  }
  
  /// Parse WAV header to find the start of PCM audio data
  /// Returns the byte offset where PCM data begins, or 0 if parsing fails
  int _parseWavHeader(Uint8List headerBytes) {
    try {
      // WAV file structure:
      // 0-3: "RIFF" (4 bytes)
      // 4-7: File size - 8 (4 bytes, little-endian)
      // 8-11: "WAVE" (4 bytes)
      // 12-15: "fmt " (4 bytes)
      // 16-19: Subchunk1Size (4 bytes, usually 16)
      // ... fmt chunk data ...
      // Then "data" chunk starts
      
      if (headerBytes.length < 44) {
        debugPrint('WakeWordService: WAV header too short: ${headerBytes.length} bytes');
        return 44; // Fallback to standard header size
      }
      
      // Verify RIFF header
      final riff = String.fromCharCodes(headerBytes.sublist(0, 4));
      if (riff != 'RIFF') {
        debugPrint('WakeWordService: Invalid WAV file - missing RIFF header');
        return 44; // Fallback
      }
      
      // Verify WAVE header
      final wave = String.fromCharCodes(headerBytes.sublist(8, 12));
      if (wave != 'WAVE') {
        debugPrint('WakeWordService: Invalid WAV file - missing WAVE header');
        return 44; // Fallback
      }
      
      // Find "data" chunk
      // Search for "data" marker (usually around byte 36-40, but can vary)
      for (int i = 12; i < headerBytes.length - 4; i++) {
        final chunkId = String.fromCharCodes(headerBytes.sublist(i, i + 4));
        if (chunkId == 'data') {
          // Found data chunk, skip "data" (4 bytes) + chunk size (4 bytes) = 8 bytes
          final dataStart = i + 8;
          debugPrint('WakeWordService: Found data chunk at byte $i, PCM data starts at $dataStart');
          return dataStart;
        }
      }
      
      // If "data" chunk not found in header, assume standard 44-byte header
      debugPrint('WakeWordService: Data chunk not found in header, using default offset 44');
      return 44;
    } catch (e) {
      debugPrint('WakeWordService: Error parsing WAV header: $e');
      return 44; // Fallback to standard header size
    }
  }
  
  /// Get temporary recording path for wake word detection
  Future<String> _getRecordingPath() async {
    try {
      final directory = await getTemporaryDirectory();
      return '${directory.path}/wake_word_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    } catch (e) {
      debugPrint('WakeWordService: Error getting recording path: $e');
      return '/tmp/wake_word_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    }
  }
  
  /// Send audio chunk to WebSocket
  /// Audio must be PCM16 (16kHz, mono, 16-bit, little-endian) and base64-encoded
  void _sendAudioChunk(Uint8List pcm16Audio) {
    if (!_isListening || _channel == null) return;
    
    try {
      // Base64 encode the PCM16 audio
      final base64Audio = base64Encode(pcm16Audio);
      
      // Send as input_audio_buffer.append message
      final message = {
        'type': 'input_audio_buffer.append',
        'audio': base64Audio,
      };
      
      _channel?.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('WakeWordService: Error sending audio chunk: $e');
    }
  }

  /// Stop OpenAI Realtime API wake word detection
  Future<void> stop() async {
    if (!_isListening) return;
    
    try {
      _audioStreamTimer?.cancel();
      _audioStreamTimer = null;
      
      _audioCommitTimer?.cancel();
      _audioCommitTimer = null;
      
      _audioStream?.cancel();
      _audioStream = null;
      
      await _recorder?.stop();
      await _recorder?.dispose();
      _recorder = null;
      
      await _channel?.sink.close();
      _channel = null;
      
      _isListening = false;
      debugPrint('WakeWordService: OpenAI Realtime API wake word detection stopped');
    } catch (e) {
      debugPrint('WakeWordService: Error stopping wake word detection: $e');
      _isListening = false;
    }
  }

  void dispose() {
    stop();
  }
}
