import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../models/game_settings.dart';
import '../utils/text_helpers.dart';
import '../services/voice_pipeline_service.dart';
import '../services/storage_service.dart';
import '../services/reminder_intent_handler.dart';
import '../services/reminder_scheduler_service.dart';
import '../services/note_tools_handler.dart';
import '../services/weather_service.dart';
import '../game/game_controller.dart';
import '../game/lesson_phase.dart';
import 'reminder_provider.dart';
import 'custom_quiz_provider.dart';

class VoiceProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  late final VoicePipelineService _pipeline;
  late final GameController _gameController;
  ReminderIntentHandler? _reminderIntentHandler;
  ReminderProvider? _reminderProvider;
  final NoteToolsHandler _noteToolsHandler = NoteToolsHandler();

  VoiceState _state = VoiceState.sleep;
  Conversation? _conversation;
  bool _isWakeWordActive = false;
  String? _error;
  String? _lastTranscription;
  String? _lastResponse;

  VoiceProvider(StorageService storageService) {
    _pipeline = VoicePipelineService(storageService);
    _pipeline.noteToolsHandler = _noteToolsHandler;
    _gameController = GameController();
    _setupPipelineCallbacks();
    _setupGameController();
    _setupLessonModeCallbacks();
  }

  /// Wire lesson mode callbacks from NoteToolsHandler
  void _setupLessonModeCallbacks() {
    _noteToolsHandler.onStartLessonMode = (category) async {
      debugPrint('VoiceProvider: onStartLessonMode callback - category: $category');
      await startLessonCategory(category);
    };

    _noteToolsHandler.onExitLessonMode = () async {
      debugPrint('VoiceProvider: onExitLessonMode callback');
      await exitLessonMode();
    };
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

  /// Set CustomQuizProvider reference (for custom quiz game mode)
  void setCustomQuizProvider(CustomQuizProvider provider) {
    _gameController.setCustomQuizProvider(provider);
    debugPrint('VoiceProvider: CustomQuizProvider set on GameController');
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

  // ============================================================
  // GAME CONTROLLER (FSM-based lesson mode)
  // ============================================================

  /// Get the game controller for UI access
  GameController get gameController => _gameController;

  /// Get the current lesson state for UI
  LessonState get lessonState => _gameController.state;

  /// Whether lesson mode is active
  bool get isLessonActive => _gameController.isActive;

  /// Callback for navigating to game page
  VoidCallback? onNavigateToGame;

  /// Setup the game controller with pipeline integration
  void _setupGameController() {
    // Wire TTS callback
    _gameController.onPlayTTS = (text) async {
      final voice = _pendingVoice ?? 'alloy';
      await _pipeline.playTTSForLesson(text, voice);
    };

    // Wire mic start callback
    _gameController.onStartMic = () async {
      final sessionId = _gameController.sessionId;
      debugPrint('VP: onStartMic callback ENTER (session=$sessionId)');

      // Stop any existing chat listening first
      debugPrint('VP: calling pauseContinuousMode');
      await _pipeline.pauseContinuousMode();
      debugPrint('VP: pauseContinuousMode returned');

      transitionTo(VoiceState.listening);
      _gameController.onMicStarted();

      debugPrint('VP: calling startLessonListening (session=$sessionId)');
      await _pipeline.startLessonListening(sessionId: sessionId);
      debugPrint('VP: startLessonListening returned');
    };

    // Wire mic stop callback (for manual stops, e.g., skip/exit)
    _gameController.onStopMic = () async {
      debugPrint('VP: onStopMic callback ENTER (session=${_gameController.sessionId})');

      // Capture session ID before async operation
      final sessionId = _gameController.sessionId;

      debugPrint('VP: calling stopLessonListening (manual)');
      final transcription = await _pipeline.stopLessonListening();
      debugPrint('VP: stopLessonListening returned: "$transcription"');

      _gameController.onMicStopped();

      if (transcription != null && transcription.isNotEmpty) {
        // Pass session ID to validate callback is still relevant
        debugPrint('VP: calling onASRResult with transcription');
        _gameController.onASRResult(transcription, sessionId: sessionId);
      } else {
        debugPrint('VP: no transcription, not calling onASRResult');
      }
    };

    // Wire auto-transcription callback (called when lesson mic auto-stops)
    _pipeline.onLessonTranscriptionComplete = (transcription, sessionId) {
      debugPrint('VP: onLessonTranscriptionComplete (session=$sessionId, text="$transcription")');
      _gameController.onMicStopped();
      _gameController.onASRResult(transcription, sessionId: sessionId);
    };

    // Wire navigation callbacks
    _gameController.onLessonStarted = () {
      onNavigateToGame?.call();
      notifyListeners();
    };

    _gameController.onLessonEnded = () {
      // Resume to paused state after lesson ends
      transitionTo(VoiceState.paused);
      notifyListeners();

      // Check for any pending reminder alerts that were queued during the game
      ReminderSchedulerService.getInstance().checkPendingAlertsOnPause();
    };

    // Forward controller notifications
    _gameController.addListener(() {
      notifyListeners();
    });
  }

  /// Configure game settings (time limit, difficulty, auto-record)
  void setGameSettings(GameSettings settings) {
    debugPrint('VoiceProvider.setGameSettings: $settings');
    _gameController.setTimeLimit(settings.timeLimit.seconds);
    _gameController.setDifficulty(settings.difficulty.dbValue);
    _gameController.setAutoRecord(settings.autoRecord);
  }

  /// Start recording manually (for when auto-record is off)
  Future<void> startGameRecording() async {
    await _gameController.startRecording();
  }

  /// Select a lesson category (doesn't start the game yet)
  void selectLessonCategory(String category) {
    debugPrint('VoiceProvider.selectLessonCategory: category=$category');
    _gameController.selectCategory(category);
    notifyListeners();
  }

  /// Start the game (after category is selected)
  Future<void> startGame() async {
    debugPrint('VoiceProvider.startGame');

    // Stop any ongoing listening/speaking first
    await _pipeline.stopContinuousMode();

    // Delegate to FSM controller
    await _gameController.startMode();
  }

  /// Start a lesson category directly (for voice commands)
  Future<void> startLessonCategory(String category) async {
    debugPrint('VoiceProvider.startLessonCategory: category=$category');

    // Stop any ongoing listening/speaking first
    await _pipeline.stopContinuousMode();

    // Delegate to FSM controller - pass category directly
    await _gameController.startMode(category);
  }

  /// Pause the game
  Future<void> pauseGame() async {
    await _gameController.pauseGame();
    notifyListeners();
  }

  /// Resume the game
  Future<void> resumeGame() async {
    await _gameController.resumeGame();
    notifyListeners();
  }

  /// Skip the current question
  Future<void> skipQuestion() async {
    await _gameController.skipQuestion();
  }

  /// Whether the game is paused
  bool get isGamePaused => _gameController.isPaused;

  /// Whether a category is selected (ready to start)
  bool get isGameSelected => _gameController.isSelected;

  /// Whether the game is actively running
  bool get isGameRunning => _gameController.isGameRunning;

  /// Exit lesson mode - delegates to FSM controller
  Future<void> exitLessonMode() async {
    await _gameController.exitMode();
  }

  /// End lesson mode immediately (for menu button)
  /// Forces immediate exit - stops TTS, mic, and all listening
  Future<void> endLessonMode() async {
    // Always force stop audio first (even if game state is unexpected)
    await _pipeline.forceStopAudio();

    if (_gameController.isActive || _gameController.isSelected) {
      // Force exit without goodbye TTS
      _gameController.forceExit();

      // Stop any audio playback and listening
      await _pipeline.stopContinuousMode();

      // Return to paused state
      transitionTo(VoiceState.paused);
    }
  }


  /// Setup callbacks from pipeline service
  void _setupPipelineCallbacks() {
    _pipeline.onStateChange = (state) {
      transitionTo(state);
    };

    // Wire TTS completion callback for lesson mode FSM
    _pipeline.onTTSPlaybackComplete = () {
      if (_gameController.isActive) {
        // Pass current session ID to validate callback
        final sessionId = _gameController.sessionId;
        debugPrint('VoiceProvider: TTS complete, notifying game controller (session $sessionId)');
        _gameController.onTTSFinished(sessionId: sessionId);
      }
    };

    _pipeline.onTranscription = (transcription) {
      _lastTranscription = transcription;

      // EXCLUSIVITY: If lesson mode is active, it owns the mic
      // Only forward transcriptions during LISTEN phase
      if (_gameController.isActive) {
        if (_gameController.phase == LessonPhase.listen) {
          debugPrint('VoiceProvider: Lesson mode - forwarding transcription to controller');
          final sessionId = _gameController.sessionId;
          _gameController.onASRResult(transcription, sessionId: sessionId);
        } else {
          debugPrint('VoiceProvider: Lesson mode active but not in LISTEN phase - ignoring transcription');
        }
        return;
      }

      // Only add user message to conversation if NOT in reminder flow
      // This prevents LLM from seeing reminder flow inputs and responding to them
      if (_reminderIntentHandler == null || !_reminderIntentHandler!.isInFlow) {
        addUserMessage(transcription);
      } else {
        debugPrint('VoiceProvider: Skipping adding user message to conversation (in reminder flow)');
      }

      // Note: Reminder intent detection and flow initiation happens in onProcessReminderIntent
      // to ensure we can return a response immediately

      notifyListeners();
    };

    _pipeline.onResponse = (response) {
      _lastResponse = response;
      addAssistantMessage(response);
      notifyListeners();
    };

    _pipeline.onError = (error) {
      _error = error;
      setError(error);
    };

    // NOTE: Old wizard-based reminder flow is disabled.
    // All schedule/reminder operations now go through AI function calling (create_alert, etc.)
    _pipeline.onProcessReminderIntent = (userInput, remindersList) async {
      // Always return null to let the AI handle schedule requests via function calling
      return null;
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
  AIServiceStatus? _pendingSubscriptionStatus;
  
  /// Start a new voice session - always starts in sleep mode waiting for wake word
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
    AIServiceStatus? subscriptionStatus,
  }) async {
    // Ensure pipeline is fully stopped before starting new session
    await _pipeline.stopContinuousMode();
    await _pipeline.stopSleepMode(); // Stop any existing sleep mode
    await Future.delayed(const Duration(milliseconds: 200)); // Ensure cleanup completes
    
    // Clear conversation and reset state
    _conversation = Conversation.start(agentId);
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;
    _state = VoiceState.sleep; // Start from sleep, waiting for wake word
    _isWakeWordActive = true;
    
    // Store session parameters for when wake word is detected
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
    _pendingSubscriptionStatus = subscriptionStatus;
    
    notifyListeners();
    
    // Start sleep mode with OpenAI Realtime API wake word detection
    debugPrint('Starting session in sleep mode - waiting for "Hey Millie" wake word');
    await _pipeline.startSleepMode(onWakeWordDetected: _activateSessionFromSleep);
  }
  
  /// Activate session from sleep mode when wake word is detected
  Future<void> _activateSessionFromSleep() async {
    debugPrint('Wake word detected - activating session from sleep mode');
    
    // Stop sleep mode wake word detection
    await _pipeline.stopSleepMode();
    
    // Now activate the session with intro/listening
    if (_pendingIntroMessage != null && _pendingIntroMessage!.isNotEmpty && _pendingVoice != null) {
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
        subscriptionStatus: _pendingSubscriptionStatus,
        getConversationHistory: () => getConversationHistory(),
      );
    } else {
      // No intro message, just start listening immediately
      // Process personality prompt to replace {agent_name}
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
        subscriptionStatus: _pendingSubscriptionStatus,
        getConversationHistory: () => getConversationHistory(),
      );
    }
    
    // Don't clear pending parameters - we need them for reminder alerts
    // They'll be cleared when the session ends (endSession) or a new session starts
  }
  
  /// Handle state transitions
  void transitionTo(VoiceState newState) {
    final previousState = _state;
    _state = newState;
    
    // Update wake word activation based on state (just for UI display)
    if (newState == VoiceState.paused || newState == VoiceState.sleep) {
      _isWakeWordActive = false; // No voice activation, just manual controls
      
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
    
    // Pause continuous mode (stops recording but keeps context)
    await _pipeline.pauseContinuousMode();
    
    _state = VoiceState.paused;
    _isWakeWordActive = false; // No voice activation, just manual controls
    notifyListeners();
    
    // No wake word detection - just wait for manual play/double-tap
  }
  
  /// Resume from pause or sleep (manual only - play button or double-tap)
  Future<void> resume() async {
    debugPrint('resume() called - current state: $_state');
    // Allow resume from paused, sleep, or processing state
    if (_state != VoiceState.paused && _state != VoiceState.sleep && _state != VoiceState.processing) {
      debugPrint('Cannot resume - state is $_state (not paused, sleep, or processing)');
      return;
    }
    
    debugPrint('Resuming from $_state...');
    
    // Stop sleep mode (no-op, but kept for consistency)
    await _pipeline.stopSleepMode();
    
    // If resuming from pause, resume continuous mode (restarts listening with history)
    if (_state == VoiceState.paused) {
      await _pipeline.resumeContinuousMode();
      _state = VoiceState.listening;
      _isWakeWordActive = false;
    } else if (_state == VoiceState.sleep) {
      // If resuming from sleep, activate the pending session
      await _activateSessionFromSleep();
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
    // Stop current session and sleep mode
    await _pipeline.stopContinuousMode();
    await _pipeline.stopSleepMode();
    
    // Clear conversation
    _conversation = Conversation.start(agentId);
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;
    _state = VoiceState.sleep;
    _isWakeWordActive = false; // No voice activation, just manual controls
    
    // Restore pending session parameters if they exist, otherwise we need them from face_page
    // The face_page will call startSession() again after refreshSession()
    
    notifyListeners();
  }
  
  /// Build reminder announcement message for conversational format
  String _buildReminderAnnouncementMessage(Reminder reminder) {
    // Get username for greeting
    final username = _pendingUsername ?? 'there';
    
    // Get the main alert time (eventTime if set, otherwise scheduledAt)
    final alertTime = reminder.eventTime ?? reminder.scheduledAt;
    final timeStr = _formatTime(alertTime);
    
    // Build natural greeting and time statement
    String announcement = "Hey $username, it's $timeStr. Time to ${reminder.title.toLowerCase()}";
    
    // Add notes if they exist
    final notes = reminder.metadata?['notes'] as String?;
    if (notes != null && notes.isNotEmpty) {
      announcement += ". Don't forget ${notes.toLowerCase()}";
    }
    
    return announcement;
  }
  
  /// Format time in a natural way (e.g., "8 AM" or "3:00 PM")
  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    
    // If minutes are 0, just show hour (e.g., "8 AM"), otherwise show minutes (e.g., "3:30 PM")
    if (minute == 0) {
      return '$displayHour $period';
    } else {
      final minuteStr = minute.toString().padLeft(2, '0');
      return '$displayHour:$minuteStr $period';
    }
  }
  
  /// Trigger reminder alert - starts fresh conversation with reminder context
  /// Only works when in paused or sleep state (doesn't interrupt active conversations)
  Future<bool> triggerReminderFromAlert(Reminder reminder) async {
    // Only trigger if paused or sleep - don't interrupt active conversations
    if (_state != VoiceState.paused && _state != VoiceState.sleep) {
      debugPrint('Reminder trigger skipped - active conversation in progress (state: $_state)');
      return false;
    }
    
    // Ensure we have pending session parameters (from face page)
    if (_pendingAgentId == null || _pendingVoice == null) {
      debugPrint('Cannot trigger reminder - no active session context');
      return false;
    }
    
    debugPrint('Triggering reminder alert: ${reminder.title}');
    
    try {
      // 1. Stop any existing session activity (like refresh)
      await _pipeline.stopContinuousMode();
      await _pipeline.stopSleepMode();
      
      // 2. Clear conversation context (fresh start)
      _conversation = Conversation.start(_pendingAgentId!);
      _lastTranscription = null;
      _lastResponse = null;
      _error = null;
      
      // 3. Build reminder announcement message
      final reminderMessage = _buildReminderAnnouncementMessage(reminder);
      
      debugPrint('Reminder message: $reminderMessage');
      
      // 4. Add the reminder announcement to conversation history so AI has context
      addAssistantMessage(reminderMessage);
      
      // 5. Process personality prompt to replace {agent_name}
      final processedPersonalityPrompt = _pendingPersonalityPrompt != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
          : null;
      
      // 6. Immediately activate session with reminder (not intro)
      // This will play reminder announcement then go to listening
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
        subscriptionStatus: _pendingSubscriptionStatus,
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
    // Stop everything and wait a moment to ensure cleanup
    await _pipeline.stopContinuousMode();
    await Future.delayed(const Duration(milliseconds: 300)); // Ensure everything stops
    
    _conversation = null;
    _state = VoiceState.sleep;
    _isWakeWordActive = false;
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;
    
    // Clear pending session parameters
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
    _pendingSubscriptionStatus = null;

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
  
  // Voice trigger checks removed - only manual controls (play/pause buttons and double-tap)
  
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
  /// Used by ChatPage for text input, and GamePage for button selections
  Future<String?> sendTextMessage({
    required String text,
    bool playAudio = true,
    bool resumeListening = false,
  }) async {
    if (text.trim().isEmpty) return null;

    // Ensure pipeline has context configured (in case user started on text page)
    // This sets up the pipeline with pending session values if not already configured
    if (_conversation != null && _pendingPersonalityPrompt != null) {
      final processedPersonalityPrompt = _pendingPersonalityPrompt != null && _pendingAgentName != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
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
        subscriptionStatus: _pendingSubscriptionStatus,
        getConversationHistory: () => getConversationHistory(),
      );
    }

    // Add user message to conversation
    addUserMessage(text);

    // Transition to processing state
    transitionTo(VoiceState.processing);

    try {
      // NOTE: Old wizard-based reminder flow is disabled for text mode too.
      // All schedule/reminder operations now go through AI function calling (create_alert, etc.)

      // Process through pipeline (will call LLM and optionally TTS)
      // Note: The onResponse callback already adds the assistant message to conversation
      final response = await _pipeline.processTextMessage(
        text,
        playAudio: playAudio,
        voice: _pendingVoice,
      );

      if (response != null) {
        // Message already added via onResponse callback
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
        // Game mode: go back to listening after response
        transitionTo(VoiceState.listening);
        _pipeline.startListening();
      } else {
        // Chat mode: pause after response
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
  /// Returns the path to the recording file
  Future<String?> startTranscriptionRecording() async {
    return await _pipeline.startTranscriptionRecording();
  }
  
  /// Stop transcription recording and get transcribed text
  Future<String?> stopAndTranscribe() async {
    final audioPath = await _pipeline.stopTranscriptionRecording();
    if (audioPath == null) return null;
    
    final transcription = await _pipeline.transcribeAudio(audioPath);
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
    
    // Process the audio through the pipeline
    // Process personality prompt to replace {agent_name}
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

