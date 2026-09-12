import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../utils/text_helpers.dart';
import '../services/voice_pipeline_service.dart';
import '../services/realtime_voice_service.dart';
import '../services/storage_service.dart';
import '../services/reminder_intent_handler.dart';
import '../services/reminder_scheduler_service.dart';
import '../services/note_tools_handler.dart';
import '../services/weather_service.dart';
import '../services/openai_service.dart' show ToolCall;
import 'reminder_provider.dart';
import 'openclaw_provider.dart';

class VoiceProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  late final VoicePipelineService _pipeline;
  late final RealtimeVoiceService _realtimeService;
  ReminderIntentHandler? _reminderIntentHandler;
  ReminderProvider? _reminderProvider;
  OpenClawProvider? _openClawProvider;

  final NoteToolsHandler _noteToolsHandler = NoteToolsHandler();

  VoiceState _state = VoiceState.sleep;
  Conversation? _conversation;
  bool _isWakeWordActive = false;
  String? _error;
  String? _lastTranscription;
  String? _lastResponse;

  /// Voice mode: 'turn_taking' or 'realtime'
  String _voiceMode = 'turn_taking';

  /// Whether we're using realtime mode for the current session
  bool get isRealtimeMode => _voiceMode == 'realtime';

  VoiceProvider(StorageService storageService) {
    _pipeline = VoicePipelineService(storageService);
    _pipeline.noteToolsHandler = _noteToolsHandler;
    _realtimeService = RealtimeVoiceService();
    _realtimeService.noteToolsHandler = _noteToolsHandler;
    _setupPipelineCallbacks();
    _setupRealtimeCallbacks();
  }

  /// Set ReminderProvider reference (call this after ReminderProvider is initialized)
  void setReminderProvider(ReminderProvider reminderProvider) {
    _reminderProvider = reminderProvider;
    _reminderIntentHandler = ReminderIntentHandler(reminderProvider);
    // Also inject into note tools handler for unified AI schedule operations
    _noteToolsHandler.setReminderProvider(reminderProvider);
    debugPrint('VoiceProvider: ReminderIntentHandler and schedule tools initialized');
  }

  /// Set up WeatherService with API key
  void setWeatherApiKey(String apiKey) {
    final weatherService = WeatherService(apiKey);
    _noteToolsHandler.setWeatherService(weatherService);
    debugPrint('VoiceProvider: WeatherService initialized');
  }

  /// Set OpenAI API key for realtime voice service
  void setOpenAIApiKey(String apiKey) {
    _realtimeService.setApiKey(apiKey);
    debugPrint('VoiceProvider: OpenAI API key set for realtime service');
  }

  /// Set OpenClawProvider reference (for alternative LLM routing in conversation mode)
  void setOpenClawProvider(OpenClawProvider provider) {
    _openClawProvider = provider;
    // Listen for changes to update the pipeline's alternative handler
    provider.addListener(_updateOpenClawHandler);
    _updateOpenClawHandler();
    debugPrint('VoiceProvider: OpenClawProvider set');
  }

  /// Update the pipeline's alternative LLM handler based on OpenClaw state
  void _updateOpenClawHandler() {
    // OpenClaw integration - disabled by default
    _pipeline.alternativeLLMHandler = null;
    debugPrint('VoiceProvider: OpenClaw disabled - using default LLM');
  }

  /// Handle message via OpenClaw
  Future<String?> _handleOpenClawMessage({
    required String userMessage,
    required String systemPrompt,
    List<Map<String, dynamic>>? tools,
    List<Map<String, dynamic>>? conversationHistory,
  }) async {
    if (_openClawProvider == null || !_openClawProvider!.enabled) {
      return null; // Fall back to default LLM
    }

    try {
      debugPrint('VoiceProvider: Sending to OpenClaw');
      final response = await _openClawProvider!.sendMessage(
        userMessage,
        systemPrompt: systemPrompt,
        tools: tools,
        conversationHistory: conversationHistory,
      );

      if (response == null) {
        final errorMessage =
            "I'm having trouble connecting. You may need to check your Brain settings.";
        debugPrint('VoiceProvider: OpenClaw error - ${_openClawProvider!.error}');
        return errorMessage;
      }

      // Process any tool calls from OpenClaw
      if (response.hasToolCalls) {
        debugPrint(
            'VoiceProvider: Processing ${response.toolCalls.length} tool call(s) from OpenClaw');

        String? lastToolMessage;
        for (final toolCall in response.toolCalls) {
          debugPrint('VoiceProvider: Executing tool: ${toolCall.name}');

          final internalToolCall = ToolCall(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.input,
          );

          final result = await _noteToolsHandler.executeTool(internalToolCall);
          debugPrint(
              'VoiceProvider: Tool result: ${result.success} - ${result.message}');

          lastToolMessage = result.message;
        }

        if (response.hasText) {
          return response.text;
        } else if (lastToolMessage != null) {
          return lastToolMessage;
        }
      }

      return response.text;
    } catch (e) {
      debugPrint('VoiceProvider: OpenClaw exception - $e');
      return "I'm having trouble connecting. You may need to check your Brain settings.";
    }
  }

  /// Get the note tools handler for AI note operations
  NoteToolsHandler get noteToolsHandler => _noteToolsHandler;

  /// Get the currently active note (if any)
  Note? get activeNote => _noteToolsHandler.activeNote;

  /// Set callback for when active note changes
  void setOnActiveNoteChanged(Function(Note?) callback) {
    _noteToolsHandler.onActiveNoteChanged = (note) {
      callback(note);
      notifyListeners();
    };
  }

  VoiceState get state => _state;
  FaceState get faceState => _state.toFaceState;
  Conversation? get conversation => _conversation;
  bool get isWakeWordActive => _isWakeWordActive;
  String? get error => _error;
  String? get lastTranscription => _lastTranscription;
  String? get lastResponse => _lastResponse;

  bool get isSessionActive => _state.isSessionActive;
  bool get isMicActive => _state.isMicActive;
  bool get isPaused => _state == VoiceState.paused;
  bool get isRecording => _pipeline.isRecording;

  /// Speak text using TTS (for translator, etc.)
  Future<void> speakText(String text, {String? voice}) async {
    debugPrint(
        'VoiceProvider: Speaking text: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
    await _pipeline.generateAndPlayTTS(text, voice ?? _pendingVoice ?? 'alloy');
  }

  /// Setup callbacks from pipeline service
  void _setupPipelineCallbacks() {
    _pipeline.onStateChange = (state) {
      transitionTo(state);
    };

    _pipeline.onTranscription = (transcription) {
      _lastTranscription = transcription;

      // Only add user message to conversation if NOT in reminder flow
      if (_reminderIntentHandler == null || !_reminderIntentHandler!.isInFlow) {
        addUserMessage(transcription);
      } else {
        debugPrint(
            'VoiceProvider: Skipping adding user message to conversation (in reminder flow)');
      }

      notifyListeners();
    };

    _pipeline.onResponse = (response) async {
      _lastResponse = response;
      addAssistantMessage(response);
      notifyListeners();
    };

    _pipeline.onError = (error) {
      _error = error;
      setError(error);
    };

    // All schedule/reminder operations go through AI function calling
    _pipeline.onProcessReminderIntent = (userInput, remindersList) async {
      return null;
    };
  }

  /// Setup callbacks from realtime voice service
  void _setupRealtimeCallbacks() {
    _realtimeService.onStateChange = (state) {
      // Map RealtimeVoiceState to VoiceState
      switch (state) {
        case RealtimeVoiceState.idle:
          transitionTo(VoiceState.paused);
        case RealtimeVoiceState.connecting:
          transitionTo(VoiceState.processing);
        case RealtimeVoiceState.listening:
          transitionTo(VoiceState.listening);
        case RealtimeVoiceState.processing:
          transitionTo(VoiceState.processing);
        case RealtimeVoiceState.speaking:
          transitionTo(VoiceState.speaking);
      }
    };

    _realtimeService.onTranscription = (transcription) {
      _lastTranscription = transcription;
      addUserMessage(transcription);
      notifyListeners();
    };

    _realtimeService.onResponse = (response) {
      _lastResponse = response;
      addAssistantMessage(response);
      notifyListeners();
    };

    _realtimeService.onError = (error) {
      _error = error;
      setError(error);
    };

    _realtimeService.onPauseRequested = () {
      debugPrint('VoiceProvider: Realtime pause requested');
      transitionTo(VoiceState.paused);
    };
  }

  // Store pending session parameters for activation from sleep mode
  String? _pendingAgentId;
  String? _pendingAgentName;
  String? _pendingIntroMessage;
  String? _pendingVoice;
  String? _pendingUsername;
  String? _pendingBio;
  String? _pendingPersonalityPrompt;
  String? _pendingAiServiceId;
  String? _pendingUserId;
  String? _pendingUserEmail;

  /// Start a new voice session
  /// For turn_taking mode: starts in sleep mode waiting for wake word
  /// For realtime mode: starts directly with streaming connection
  Future<void> startSession(
    String agentId, {
    String? agentName,
    String? introMessage,
    String? voice,
    String? username,
    String? bio,
    String? personalityPrompt,
    String? aiServiceId,
    String? userId,
    String? userEmail,
    String voiceMode = 'turn_taking',
  }) async {
    // Store voice mode for this session
    _voiceMode = voiceMode;
    debugPrint('VoiceProvider: Starting session with voiceMode=$_voiceMode');

    // Ensure both services are fully stopped before starting new session
    await _pipeline.stopContinuousMode();
    await _pipeline.stopSleepMode();
    await _realtimeService.stopConversation();
    await Future.delayed(const Duration(milliseconds: 200));

    // Clear conversation and reset state
    _conversation = Conversation.start(agentId);
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;
    _state = VoiceState.sleep;
    _isWakeWordActive = !isRealtimeMode; // No wake word in realtime mode

    // Store session parameters for when wake word is detected (or immediate use in realtime)
    _pendingAgentId = agentId;
    _pendingAgentName = agentName;
    _pendingIntroMessage = introMessage;
    _pendingVoice = voice;
    _pendingUsername = username;
    _pendingBio = bio;
    _pendingPersonalityPrompt = personalityPrompt;
    _pendingAiServiceId = aiServiceId;
    _pendingUserId = userId;
    _pendingUserEmail = userEmail;

    notifyListeners();

    if (isRealtimeMode) {
      // Realtime mode: start directly without wake word
      debugPrint('VoiceProvider: Starting realtime session immediately');
      await _startRealtimeSession();
    } else {
      // Turn-taking mode: start sleep mode with wake word detection
      debugPrint(
          'Starting session in sleep mode - waiting for "Hey Millie" wake word');
      await _pipeline.startSleepMode(onWakeWordDetected: _activateSessionFromSleep);
    }
  }

  /// Start realtime streaming session
  Future<void> _startRealtimeSession() async {
    // Process personality prompt
    final processedPersonalityPrompt = _pendingPersonalityPrompt != null
        ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
        : 'You are a helpful AI assistant.';

    // Build system prompt with context
    final systemPrompt = _buildRealtimeSystemPrompt(processedPersonalityPrompt);

    // Process greeting message
    String? greeting;
    if (_pendingIntroMessage != null && _pendingIntroMessage!.isNotEmpty) {
      greeting = replaceIntroMessagePlaceholders(
        _pendingIntroMessage!,
        _pendingUsername,
        _pendingAgentName,
      );
    }

    // Start realtime conversation
    await _realtimeService.startConversation(
      systemPrompt: systemPrompt,
      voice: _pendingVoice ?? 'alloy',
      greeting: greeting,
    );
  }

  /// Build system prompt for realtime mode
  String _buildRealtimeSystemPrompt(String personalityPrompt) {
    final buffer = StringBuffer();
    buffer.writeln(personalityPrompt);
    buffer.writeln();
    buffer.writeln('Current date/time: ${DateTime.now().toIso8601String()}');
    if (_pendingUsername != null) {
      buffer.writeln('User\'s name: $_pendingUsername');
    }
    if (_pendingBio != null && _pendingBio!.isNotEmpty) {
      buffer.writeln('User bio: $_pendingBio');
    }
    return buffer.toString();
  }

  /// Activate session from sleep mode when wake word is detected
  Future<void> _activateSessionFromSleep() async {
    debugPrint('Wake word detected - activating session from sleep mode');

    // Stop sleep mode wake word detection
    await _pipeline.stopSleepMode();

    // Now activate the session with intro/listening
    if (_pendingIntroMessage != null &&
        _pendingIntroMessage!.isNotEmpty &&
        _pendingVoice != null) {
      // Replace {username} and {agent_name} placeholders safely
      final processedMessage = replaceIntroMessagePlaceholders(
        _pendingIntroMessage!,
        _pendingUsername,
        _pendingAgentName,
      );

      debugPrint('Activating session with intro: $processedMessage');

      // Process personality prompt to replace {agent_name}
      final processedPersonalityPrompt = _pendingPersonalityPrompt != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
          : null;

      await _pipeline.playIntroMessage(
        processedMessage,
        _pendingVoice!,
        autoStartListening: true,
        agentId: _pendingAgentId!,
        personalityPrompt: processedPersonalityPrompt,
        aiServiceId: _pendingAiServiceId,
        username: _pendingUsername,
        bio: _pendingBio,
        userId: _pendingUserId,
        userEmail: _pendingUserEmail,
        getConversationHistory: () => getConversationHistory(),
      );
    } else {
      // No intro message, just start listening immediately
      final processedPersonalityPrompt = _pendingPersonalityPrompt != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
          : null;

      _state = VoiceState.listening;
      notifyListeners();
      await _pipeline.startListening(
        continuousMode: true,
        agentId: _pendingAgentId!,
        personalityPrompt: processedPersonalityPrompt,
        aiServiceId: _pendingAiServiceId,
        voice: _pendingVoice ?? 'alloy',
        username: _pendingUsername,
        bio: _pendingBio,
        userId: _pendingUserId,
        userEmail: _pendingUserEmail,
        getConversationHistory: () => getConversationHistory(),
      );
    }
  }

  /// Handle state transitions
  void transitionTo(VoiceState newState) {
    final previousState = _state;
    _state = newState;

    // Update wake word activation based on state
    if (newState == VoiceState.paused || newState == VoiceState.sleep) {
      _isWakeWordActive = false;

      // Check for pending voice alerts when transitioning to paused
      if (newState == VoiceState.paused) {
        final schedulerService = ReminderSchedulerService.getInstance();
        schedulerService.checkPendingAlertsOnPause();
      }
    } else {
      _isWakeWordActive = false;
    }

    debugPrint('Voice state: $previousState -> $newState');
    notifyListeners();
  }

  /// Pause the session (preserves context)
  Future<void> pause() async {
    if (_state == VoiceState.sleep) return;

    if (isRealtimeMode) {
      _realtimeService.pause();
    } else {
      await _pipeline.pauseContinuousMode();
    }

    _state = VoiceState.paused;
    _isWakeWordActive = false;
    notifyListeners();
  }

  /// Resume from pause or sleep
  Future<void> resume() async {
    debugPrint('resume() called - current state: $_state, mode: $_voiceMode');
    if (_state != VoiceState.paused &&
        _state != VoiceState.sleep &&
        _state != VoiceState.processing) {
      debugPrint(
          'Cannot resume - state is $_state (not paused, sleep, or processing)');
      return;
    }

    debugPrint('Resuming from $_state...');

    if (isRealtimeMode) {
      await _realtimeService.resume();
      _state = VoiceState.listening;
    } else {
      await _pipeline.stopSleepMode();

      if (_state == VoiceState.paused) {
        await _pipeline.resumeContinuousMode();
        _state = VoiceState.listening;
        _isWakeWordActive = false;
      } else if (_state == VoiceState.sleep) {
        await _activateSessionFromSleep();
      }
    }

    notifyListeners();
    debugPrint('Resume complete - state is now $_state');
  }

  /// Toggle pause/play
  Future<void> togglePause() async {
    if (_state == VoiceState.paused) {
      await resume();
    } else if (_state.isSessionActive) {
      await pause();
    }
  }

  /// Refresh session (clear context, go back to sleep mode)
  Future<void> refreshSession(String agentId) async {
    await _pipeline.stopContinuousMode();
    await _pipeline.stopSleepMode();

    _conversation = Conversation.start(agentId);
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;
    _state = VoiceState.sleep;
    _isWakeWordActive = false;

    notifyListeners();
  }

  /// Build reminder announcement message for conversational format
  String _buildReminderAnnouncementMessage(Reminder reminder) {
    final username = _pendingUsername ?? 'there';

    final alertTime = reminder.eventTime ?? reminder.scheduledAt;
    final timeStr = _formatTime(alertTime);

    String announcement =
        "Hey $username, it's $timeStr. Time to ${reminder.title.toLowerCase()}";

    final notes = reminder.metadata?['notes'] as String?;
    if (notes != null && notes.isNotEmpty) {
      announcement += ". Don't forget ${notes.toLowerCase()}";
    }

    return announcement;
  }

  /// Format time in a natural way
  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

    if (minute == 0) {
      return '$displayHour $period';
    } else {
      final minuteStr = minute.toString().padLeft(2, '0');
      return '$displayHour:$minuteStr $period';
    }
  }

  /// Trigger reminder alert
  Future<bool> triggerReminderFromAlert(Reminder reminder) async {
    if (_state != VoiceState.paused && _state != VoiceState.sleep) {
      debugPrint(
          'Reminder trigger skipped - active conversation in progress (state: $_state)');
      return false;
    }

    if (_pendingAgentId == null || _pendingVoice == null) {
      debugPrint('Cannot trigger reminder - no active session context');
      return false;
    }

    debugPrint('Triggering reminder alert: ${reminder.title}');

    try {
      await _pipeline.stopContinuousMode();
      await _pipeline.stopSleepMode();

      _conversation = Conversation.start(_pendingAgentId!);
      _lastTranscription = null;
      _lastResponse = null;
      _error = null;

      final reminderMessage = _buildReminderAnnouncementMessage(reminder);

      debugPrint('Reminder message: $reminderMessage');

      addAssistantMessage(reminderMessage);

      final processedPersonalityPrompt = _pendingPersonalityPrompt != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
          : null;

      await _pipeline.playIntroMessage(
        reminderMessage,
        _pendingVoice!,
        autoStartListening: true,
        agentId: _pendingAgentId!,
        personalityPrompt: processedPersonalityPrompt,
        aiServiceId: _pendingAiServiceId,
        username: _pendingUsername,
        bio: _pendingBio,
        userId: _pendingUserId,
        userEmail: _pendingUserEmail,
        getConversationHistory: () => getConversationHistory(),
      );

      debugPrint('Reminder alert triggered successfully');
      return true;
    } catch (e) {
      debugPrint('Error triggering reminder alert: $e');
      _error = 'Failed to trigger reminder';
      notifyListeners();
      return false;
    }
  }

  /// End session completely
  Future<void> endSession() async {
    debugPrint('VoiceProvider: endSession - shutting down all AI services (mode: $_voiceMode)');

    // Stop both services to ensure clean shutdown
    await _realtimeService.stopConversation();
    await _pipeline.forceStopAudio();
    await _pipeline.stopContinuousMode();
    await Future.delayed(const Duration(milliseconds: 300));

    _conversation = null;
    _state = VoiceState.sleep;
    _isWakeWordActive = false;
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;
    _voiceMode = 'turn_taking'; // Reset to default

    _pendingAgentId = null;
    _pendingAgentName = null;
    _pendingIntroMessage = null;
    _pendingVoice = null;
    _pendingUsername = null;
    _pendingBio = null;
    _pendingPersonalityPrompt = null;
    _pendingAiServiceId = null;
    _pendingUserId = null;
    _pendingUserEmail = null;

    debugPrint('VoiceProvider: endSession complete - all services stopped');
    notifyListeners();
  }

  /// Add user message to conversation
  void addUserMessage(String content) {
    if (_conversation == null) return;

    final message = ConversationMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );

    _conversation = _conversation!.addMessage(message);
    _lastTranscription = content;
    notifyListeners();
  }

  /// Add assistant message to conversation
  void addAssistantMessage(String content) {
    if (_conversation == null) return;

    final message = ConversationMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: content,
      timestamp: DateTime.now(),
    );

    _conversation = _conversation!.addMessage(message);
    _lastResponse = content;
    notifyListeners();
  }

  /// Set error state
  void setError(String errorMessage) {
    _error = errorMessage;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get conversation history for LLM
  List<Map<String, String>> getConversationHistory() {
    return _conversation?.toLLMMessages() ?? [];
  }

  /// Send a text message directly (bypasses voice recording/STT)
  Future<String?> sendTextMessage({
    required String text,
    bool playAudio = true,
    bool resumeListening = false,
  }) async {
    if (text.trim().isEmpty) return null;

    // Ensure pipeline has context configured
    if (_conversation != null && _pendingPersonalityPrompt != null) {
      final processedPersonalityPrompt =
          _pendingPersonalityPrompt != null && _pendingAgentName != null
              ? replaceAgentNamePlaceholder(
                  _pendingPersonalityPrompt!, _pendingAgentName)
              : _pendingPersonalityPrompt;

      _pipeline.configureForTextMode(
        agentId: _pendingAgentId,
        personalityPrompt: processedPersonalityPrompt,
        aiServiceId: _pendingAiServiceId,
        voice: _pendingVoice,
        username: _pendingUsername,
        bio: _pendingBio,
        userId: _pendingUserId,
        userEmail: _pendingUserEmail,
        getConversationHistory: () => getConversationHistory(),
      );
    }

    addUserMessage(text);
    transitionTo(VoiceState.processing);

    try {
      final response = await _pipeline.processTextMessage(
        text,
        playAudio: playAudio,
        voice: _pendingVoice,
      );

      if (response != null) {
        return response;
      } else {
        setError('Failed to get response');
        return null;
      }
    } catch (e) {
      debugPrint('Error sending text message: $e');
      setError('Failed to send message');
      return null;
    } finally {
      if (resumeListening) {
        transitionTo(VoiceState.listening);
        _pipeline.startListening();
      } else {
        transitionTo(VoiceState.paused);
      }
    }
  }

  /// Start recording audio
  Future<void> startRecording() async {
    if (_state != VoiceState.listening) return;
    await _pipeline.startListening();
  }

  /// Start recording for transcription (ChatPage use)
  Future<String?> startTranscriptionRecording() async {
    return await _pipeline.startTranscriptionRecording();
  }

  /// Stop transcription recording and get transcribed text
  Future<String?> stopAndTranscribe({String? language = 'en'}) async {
    final audioPath = await _pipeline.stopTranscriptionRecording();
    if (audioPath == null) return null;

    final transcription =
        await _pipeline.transcribeAudio(audioPath, language: language);
    return transcription;
  }

  /// Stop recording and process audio
  Future<void> stopRecordingAndProcess({
    required Agent agent,
    required Personality personality,
    required String aiServiceId,
  }) async {
    if (!_pipeline.isRecording) return;

    final audioPath = await _pipeline.stopListening();
    if (audioPath == null) {
      setError('Failed to record audio');
      return;
    }

    final processedPersonalityPrompt = replaceAgentNamePlaceholder(
      personality.behaviorPrompt,
      agent.name,
    );

    await _pipeline.processAudio(
      audioPath,
      agentId: agent.id,
      personalityPrompt: processedPersonalityPrompt,
      aiServiceId: aiServiceId,
      voice: agent.voice,
      conversationHistory: getConversationHistory(),
    );
  }

  /// Cleanup
  void dispose() {
    _pipeline.dispose();
    super.dispose();
  }
}
