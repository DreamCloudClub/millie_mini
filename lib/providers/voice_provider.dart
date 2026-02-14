import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../utils/text_helpers.dart';
import '../services/voice_pipeline_service.dart';
import '../services/storage_service.dart';
import '../services/reminder_intent_handler.dart';
import '../services/reminder_scheduler_service.dart';
import '../services/note_tools_handler.dart';
import '../services/weather_service.dart';
import '../services/game_questions_service.dart';
import '../game/game_page_content.dart';
import 'reminder_provider.dart';

class VoiceProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  late final VoicePipelineService _pipeline;
  ReminderIntentHandler? _reminderIntentHandler;
  ReminderProvider? _reminderProvider;
  final NoteToolsHandler _noteToolsHandler = NoteToolsHandler();
  
  VoiceState _state = VoiceState.sleep;
  Conversation? _conversation;
  bool _isWakeWordActive = false;
  String? _error;
  String? _lastTranscription;
  String? _lastResponse;
  GameState _gameState = GameState.inactive;
  
  VoiceProvider(StorageService storageService) {
    _pipeline = VoicePipelineService(storageService);
    _pipeline.noteToolsHandler = _noteToolsHandler;
    _setupPipelineCallbacks();
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

  // Game state
  GameState get gameState => _gameState;
  GameType? _currentGameCategory;

  /// Callback for navigating to game page
  VoidCallback? onNavigateToGame;

  /// Start a game category - fetches first question from DB
  Future<void> startGameCategory(GameType type) async {
    debugPrint('VoiceProvider.startGameCategory: type=$type');

    // Stop any ongoing listening/speaking first
    await _pipeline.stopContinuousMode();

    _currentGameCategory = type;
    _gameState = GameState(
      isActive: true,
      type: type,
      questionCount: 0,
    );
    notifyListeners();

    // Small delay for UI to update
    await Future.delayed(const Duration(milliseconds: 200));

    // Load the first question
    await loadNextQuestion();
  }

  /// Load the next question from the database
  Future<void> loadNextQuestion() async {
    if (_currentGameCategory == null) return;

    final categoryStr = _currentGameCategory == GameType.random
        ? 'random'
        : _currentGameCategory.toString().split('.').last;

    debugPrint('VoiceProvider.loadNextQuestion: category=$categoryStr');

    final question = await GameQuestionsService.getNextQuestion(categoryStr);

    if (question == null) {
      debugPrint('VoiceProvider.loadNextQuestion: No questions found');
      final voice = _pendingVoice ?? 'alloy';
      await _pipeline.playTextToSpeech('No more questions available. Let me know if you want to try another category.', voice);
      return;
    }

    // Mark as used
    await GameQuestionsService.markAsUsed(question.id);

    // Update game state with new question (shows on screen first)
    _gameState = _gameState.copyWith(
      questionId: question.id,
      question: question.question,
      answer: question.answer,
      isAnswerRevealed: false,
      questionCount: _gameState.questionCount + 1,
    );
    notifyListeners();

    // Wait for UI to render the question before speaking
    await Future.delayed(const Duration(milliseconds: 500));

    // Speak the question
    final voice = _pendingVoice ?? 'alloy';
    transitionTo(VoiceState.speaking);
    await _pipeline.playTextToSpeech(question.question, voice);

    // Wait a moment after speaking before listening
    await Future.delayed(const Duration(milliseconds: 300));

    // Start listening for the answer
    transitionTo(VoiceState.listening);

    // Process personality prompt
    final processedPersonalityPrompt = _pendingPersonalityPrompt != null && _pendingAgentName != null
        ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
        : _pendingPersonalityPrompt;

    await _pipeline.startListening(
      continuousMode: false,  // Not continuous - game handles the loop
      agentId: _pendingAgentId,
      personalityPrompt: processedPersonalityPrompt,
      aiServiceId: _pendingAiServiceId,
      voice: voice,
      username: _pendingUsername,
      bio: _pendingBio,
      userId: _pendingUserId,
      userEmail: _pendingUserEmail,
      subscriptionStatus: _pendingSubscriptionStatus,
      getConversationHistory: () => getConversationHistory(),
    );
  }

  /// Reveal the answer for current question
  void revealGameAnswer() {
    debugPrint('VoiceProvider.revealGameAnswer: isActive=${_gameState.isActive}');
    if (_gameState.isActive && _gameState.answer != null) {
      _gameState = _gameState.copyWith(isAnswerRevealed: true);
      debugPrint('VoiceProvider.revealGameAnswer: revealed');
      notifyListeners();
    }
  }

  /// Move to next question (auto-called after answer confirmed)
  Future<void> nextGameQuestion() async {
    if (!_gameState.isActive) return;

    // Check if we should ask about changing category (every 5 questions)
    if (_gameState.questionCount > 0 && _gameState.questionCount % 5 == 0) {
      await sendTextMessage(
        text: 'You have answered ${_gameState.questionCount} questions! Would you like to continue with ${_currentGameCategory?.toString().split('.').last ?? 'this category'} or switch to something else?',
        playAudio: true,
        resumeListening: true,
      );
      return;
    }

    // Load next question
    await loadNextQuestion();
  }

  /// Handle user's answer to a game question
  Future<void> _handleGameAnswer(String userAnswer) async {
    final correctAnswer = _gameState.answer?.toLowerCase().trim() ?? '';
    final userAnswerLower = userAnswer.toLowerCase().trim();
    final voice = _pendingVoice ?? 'alloy';

    debugPrint('VoiceProvider._handleGameAnswer: user="$userAnswerLower", correct="$correctAnswer"');

    // Check if answer is correct (flexible matching)
    final isCorrect = userAnswerLower.contains(correctAnswer) ||
                      correctAnswer.contains(userAnswerLower) ||
                      _fuzzyMatch(userAnswerLower, correctAnswer);

    _gameState = _gameState.copyWith(isAnswerRevealed: true);
    notifyListeners();

    transitionTo(VoiceState.speaking);
    if (isCorrect) {
      await _pipeline.playTextToSpeech("That's right!", voice);
    } else {
      await _pipeline.playTextToSpeech('The answer is: ${_gameState.answer}', voice);
    }

    await Future.delayed(const Duration(seconds: 1));
    await loadNextQuestion();
  }

  /// Simple fuzzy match for answer checking
  bool _fuzzyMatch(String userAnswer, String correctAnswer) {
    final userWords = userAnswer.split(' ').where((w) => w.length > 2).toSet();
    final correctWords = correctAnswer.split(' ').where((w) => w.length > 2).toSet();
    return userWords.intersection(correctWords).isNotEmpty;
  }

  /// End the current game
  void endGame() {
    _gameState = GameState.inactive;
    _currentGameCategory = null;
    notifyListeners();
  }

  /// Set the current game question (called when AI fetches a question)
  void setGameQuestion(String question, String answer) {
    _gameState = GameState(
      isActive: true,
      question: question,
      answer: answer,
      isAnswerRevealed: false,
      questionCount: _gameState.questionCount + 1,
    );
    notifyListeners();
  }

  /// Reveal the current game answer (called when AI reveals it)
  void revealCurrentAnswer() {
    if (_gameState.isActive) {
      _gameState = _gameState.copyWith(isAnswerRevealed: true);
      notifyListeners();
    }
  }
  
  /// Setup callbacks from pipeline service
  void _setupPipelineCallbacks() {
    _pipeline.onStateChange = (state) {
      transitionTo(state);
    };
    
    _pipeline.onTranscription = (transcription) {
      _lastTranscription = transcription;

      // Check if we're in game mode waiting for an answer
      if (_gameState.isActive && _gameState.answer != null && !_gameState.isAnswerRevealed) {
        debugPrint('VoiceProvider: Game mode - checking answer');
        _handleGameAnswer(transcription);
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

