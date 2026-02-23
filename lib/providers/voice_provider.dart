import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../models/game_settings.dart';
import '../utils/text_helpers.dart';
import '../services/voice_pipeline_service.dart';
import '../services/storage_service.dart';
import '../services/reminder_intent_handler.dart';
import '../services/reminder_scheduler_service.dart';
import '../services/note_tools_handler.dart';
import '../services/intent_router.dart';
import '../services/weather_service.dart';
import '../services/spelling_tts_player.dart';
import '../services/reports_service.dart';
import '../game/game_controller.dart';
import '../game/lesson_phase.dart';
import 'reminder_provider.dart';
import 'custom_quiz_provider.dart';
import 'openclaw_provider.dart';
import 'reports_provider.dart';
import '../services/openai_service.dart';

class VoiceProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  late final VoicePipelineService _pipeline;
  late final GameController _gameController;
  late final SpellingTtsPlayer _spellingTtsPlayer;
  ReminderIntentHandler? _reminderIntentHandler;
  ReminderProvider? _reminderProvider;
  OpenClawProvider? _openClawProvider;
  ReportsProvider? _reportsProvider;
  bool _isInReportMode = false; // When true, bypass OpenClaw for report conversations
  bool _isAwaitingReportCheckIn = false; // True only during "Is now a good time?" question
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
    _spellingTtsPlayer = SpellingTtsPlayer(_pipeline.openAIService);
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

    _noteToolsHandler.onRefreshSession = () async {
      debugPrint('VoiceProvider: onRefreshSession callback - wiping context for game handoff');
      if (_pendingAgentId != null) {
        await refreshSession(_pendingAgentId!);
      }
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

  /// Set OpenClawProvider reference (for alternative LLM routing in conversation mode)
  void setOpenClawProvider(OpenClawProvider provider) {
    _openClawProvider = provider;
    // Listen for changes to update the pipeline's alternative handler
    provider.addListener(_updateOpenClawHandler);
    _updateOpenClawHandler();
    debugPrint('VoiceProvider: OpenClawProvider set');
  }

  /// Set ReportsProvider reference (for AI report announcements)
  void setReportsProvider(ReportsProvider provider) {
    _reportsProvider = provider;
    _noteToolsHandler.setReportsProvider(provider);

    // Wire up report announcement callback
    provider.onAnnounceReport = (report) {
      _announceReport(report);
    };

    debugPrint('VoiceProvider: ReportsProvider set');
  }

  // Store pending report for scheduled announcement (after yes/no check-in)
  Report? _pendingScheduledReport;

  /// Announce a new report via TTS (proactive announcement from schedule)
  /// First asks if it's a good time, then announces the report if user says yes
  Future<void> _announceReport(Report report) async {
    // Only announce if in paused or sleep state
    if (_state != VoiceState.paused && _state != VoiceState.sleep) {
      debugPrint('VoiceProvider: Skipping report announcement - active conversation');
      return;
    }

    debugPrint('VoiceProvider: Starting scheduled report check-in for: ${report.title}');

    // Enable report mode to bypass OpenClaw
    _isInReportMode = true;
    _isAwaitingReportCheckIn = true; // Fast-exit on "no" for this question only
    _noteToolsHandler.forcedIntents = {IntentCategory.reports}; // Force reports tools
    _updateOpenClawHandler();

    // Store the pending report so we can read it after user confirms
    _pendingScheduledReport = report;

    // Build check-in message - ask if it's a good time first
    final username = _pendingUsername ?? 'there';
    final agentName = _pendingAgentName ?? 'Millie';
    final checkInMessage = "Hey $username, it's me $agentName. Is now a good time for a quick news update?";

    // Build the full report content for when user says yes
    final reportContent = "${report.title}. ${report.summary}. ${report.content}";

    try {
      await _pipeline.stopSleepMode();

      // Process personality prompt
      final processedPersonalityPrompt = _pendingPersonalityPrompt != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
          : null;

      // Start fresh conversation with context about pending report
      _conversation = Conversation.start(_pendingAgentId ?? '');

      // Get all live reports for skip/next functionality
      final liveReports = _reportsProvider?.filteredLiveReports ?? [];

      // Find the index of the current report in the queue
      final currentIndex = liveReports.indexWhere((r) => r.id == report.id);

      // Build context with all reports so user can skip to others
      final reportsContext = StringBuffer();
      reportsContext.writeln('[SYSTEM: You have a ${report.category} news report ready to share.');
      reportsContext.writeln('');
      reportsContext.writeln('CURRENT REPORT TO ANNOUNCE:');
      reportsContext.writeln('Title: ${report.title}');
      reportsContext.writeln('Summary: ${report.summary}');
      reportsContext.writeln('Full Content: ${report.content}');

      // Include other reports in queue for skip/next
      if (liveReports.length > 1) {
        reportsContext.writeln('');
        reportsContext.writeln('OTHER REPORTS IN QUEUE (for skip/next):');
        for (var i = 0; i < liveReports.length; i++) {
          if (liveReports[i].id != report.id) {
            final r = liveReports[i];
            reportsContext.writeln('');
            reportsContext.writeln('--- REPORT (ID: ${r.id}): ${r.title} ---');
            reportsContext.writeln('Category: ${r.category}');
            reportsContext.writeln('Summary: ${r.summary}');
          }
        }
      }

      reportsContext.writeln('');
      reportsContext.writeln('INSTRUCTIONS:');
      reportsContext.writeln('1. If user says yes to check-in, read the CURRENT REPORT title and summary.');
      reportsContext.writeln('2. Then ask "Would you like to hear the full report?"');
      reportsContext.writeln('3. If yes, respond with EXACTLY: [OPEN_REPORT:${report.id}] and nothing else.');
      reportsContext.writeln('4. If no/skip/next/pass, offer the next report from the queue (read title + summary).');
      reportsContext.writeln('5. If no more reports, say "That\'s all the reports for now."]');

      addUserMessage(reportsContext.toString());
      addAssistantMessage(checkInMessage);

      // Play check-in and start listening for yes/no
      await _pipeline.playIntroMessage(
        checkInMessage,
        _pendingVoice ?? 'alloy',
        autoStartListening: true,
        agentId: _pendingAgentId ?? '',
        personalityPrompt: processedPersonalityPrompt,
        aiServiceId: _pendingAiServiceId,
        username: _pendingUsername,
        bio: _pendingBio,
        userId: _pendingUserId,
        userEmail: _pendingUserEmail,
        subscriptionStatus: _pendingSubscriptionStatus,
        getConversationHistory: () => getConversationHistory(),
      );

      // Mark as announced (we asked about it)
      await _reportsProvider?.markAnnounced(report.id);

    } catch (e) {
      debugPrint('VoiceProvider: Error in report check-in: $e');
      _pendingScheduledReport = null;
      _isInReportMode = false;
      _updateOpenClawHandler();
    }
  }

  /// Get the pending scheduled report (for AI to read after user confirms)
  Report? get pendingScheduledReport => _pendingScheduledReport;

  /// Clear the pending scheduled report
  void clearPendingScheduledReport() {
    _pendingScheduledReport = null;
  }

  /// Read a specific report aloud (triggered from UI Read button)
  /// Uses cached audio if available, otherwise generates and caches for future use
  Future<void> readReport(Report report) async {
    debugPrint('VoiceProvider: Reading report: ${report.title}');

    try {
      // Stop any current audio
      await _pipeline.forceStopAudio();

      // Check if we have cached audio
      if (report.audioUrl != null && report.audioUrl!.isNotEmpty) {
        debugPrint('VoiceProvider: Playing cached audio from ${report.audioUrl}');
        await _playReportFromUrl(report.audioUrl!);
      } else {
        // Generate TTS and cache it
        debugPrint('VoiceProvider: Generating new audio for report');
        await _generateAndCacheReportAudio(report);
      }

      // Mark as announced if not already
      if (!(_reportsProvider?.isReportAnnounced(report.id) ?? true)) {
        await _reportsProvider?.markAnnounced(report.id);
      }

    } catch (e) {
      debugPrint('VoiceProvider: Error reading report: $e');
    }
  }

  /// Play report audio from cached URL
  Future<void> _playReportFromUrl(String audioUrl) async {
    try {
      await _pipeline.playAudioFromUrl(audioUrl);
    } catch (e) {
      debugPrint('VoiceProvider: Error playing from URL: $e');
      rethrow;
    }
  }

  /// Generate TTS for report, upload to storage, cache URL in database
  Future<void> _generateAndCacheReportAudio(Report report) async {
    // Build intro + full report message
    final username = _pendingUsername ?? 'there';
    final agentName = _pendingAgentName ?? 'Millie';
    final message = "Hey $username, it's me $agentName with a report update. ${report.title}. ${report.content}";

    // Process personality prompt
    final processedPersonalityPrompt = _pendingPersonalityPrompt != null
        ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
        : null;

    // Generate TTS and play (this returns the local file path)
    final audioPath = await _pipeline.generateAndPlayTTS(
      message,
      _pendingVoice ?? 'alloy',
    );

    if (audioPath != null) {
      // Upload to Supabase Storage and get public URL
      final audioUrl = await _uploadReportAudio(report.id, audioPath);

      if (audioUrl != null) {
        // Save URL to database for future use
        await ReportsService.updateAudioUrl(report.id, audioUrl);
        debugPrint('VoiceProvider: Cached audio URL: $audioUrl');
      }
    }
  }

  /// Upload audio file to Supabase Storage
  Future<String?> _uploadReportAudio(String reportId, String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('VoiceProvider: Audio file not found: $localPath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final fileName = 'report_$reportId.mp3';

      final supabase = Supabase.instance.client;

      // Upload to 'report-audio' bucket
      await supabase.storage
          .from('report-audio')
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(
            contentType: 'audio/mpeg',
            upsert: true,
          ));

      // Get public URL
      final publicUrl = supabase.storage
          .from('report-audio')
          .getPublicUrl(fileName);

      debugPrint('VoiceProvider: Uploaded audio to $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('VoiceProvider: Error uploading audio: $e');
      return null;
    }
  }

  /// Trigger report selection - asks what report the user wants to hear
  /// Used by the Wake button on the Reports page for manual report selection
  /// [skipIntro] - if true, skips the "Hey username, it's me..." intro (used when coming from voice nav)
  Future<void> triggerReportCheckIn({bool skipIntro = false}) async {
    // Ensure we have pending session parameters
    if (_pendingAgentId == null || _pendingVoice == null) {
      debugPrint('VoiceProvider: Cannot trigger report check-in - no active session');
      return;
    }

    debugPrint('VoiceProvider: Triggering report selection (skipIntro: $skipIntro)');

    // Enable report mode - force reports tools to be loaded
    _isInReportMode = true;
    _noteToolsHandler.forcedIntents = {IntentCategory.reports}; // Force reports tools
    _updateOpenClawHandler();

    // Get live reports for context
    final liveReports = _reportsProvider?.filteredLiveReports ?? [];

    // Build selection prompt - include intro only for wake button, not voice nav
    final username = _pendingUsername ?? 'there';
    final agentName = _pendingAgentName ?? 'Millie';
    final selectionMessage = skipIntro
        ? "What report should we start with?"
        : "Hey $username, it's me $agentName. What report update should we start with?";

    try {
      // Stop any current activity
      await _pipeline.stopSleepMode();

      // Process personality prompt
      final processedPersonalityPrompt = _pendingPersonalityPrompt != null
          ? replaceAgentNamePlaceholder(_pendingPersonalityPrompt!, _pendingAgentName)
          : null;

      // Start fresh conversation context
      _conversation = Conversation.start(_pendingAgentId!);

      // Build reports context for AI - include titles and summaries only (not full content)
      if (liveReports.isNotEmpty) {
        final reportsContext = StringBuffer();
        reportsContext.writeln('[SYSTEM: You have ${liveReports.length} reports ready. Here they are:');
        for (var i = 0; i < liveReports.length; i++) {
          final r = liveReports[i];
          reportsContext.writeln('');
          reportsContext.writeln('REPORT ${i + 1} (ID: ${r.id}): ${r.title}');
          reportsContext.writeln('Category: ${r.category}');
          reportsContext.writeln('Summary: ${r.summary}');
        }
        reportsContext.writeln('');
        reportsContext.writeln('INSTRUCTIONS:');
        reportsContext.writeln('1. When user says "start at the top", "first one", "open the first", or similar - immediately read Report 1 title and summary, then ask "Would you like to hear the full report?"');
        reportsContext.writeln('2. If user names a specific topic, find the matching report and read its title/summary.');
        reportsContext.writeln('3. If user says YES to full report, respond with ONLY: [OPEN_REPORT:the_report_id] - nothing else.');
        reportsContext.writeln('4. If user says no/skip/next/pass, move to the next report and read its title/summary.');
        reportsContext.writeln('5. If no more reports, say "That\'s all the reports for now."');
        reportsContext.writeln(']');
        addUserMessage(reportsContext.toString());
      } else {
        addUserMessage('[SYSTEM: No reports available right now.]');
      }

      addAssistantMessage(selectionMessage);

      // Play selection prompt and start listening
      await _pipeline.playIntroMessage(
        selectionMessage,
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

    } catch (e) {
      debugPrint('VoiceProvider: Error triggering report selection: $e');
      // Reset report mode on error
      _isInReportMode = false;
      _updateOpenClawHandler();
    }
  }

  /// Exit report mode - re-enables OpenClaw if it was enabled
  void exitReportMode() {
    if (_isInReportMode) {
      _isInReportMode = false;
      _isAwaitingReportCheckIn = false;
      _pendingScheduledReport = null;
      _noteToolsHandler.forcedIntents.clear(); // Clear forced reports tools
      _updateOpenClawHandler();
      debugPrint('VoiceProvider: Exited report mode');
    }
  }

  /// Check if transcription is a negative/decline response
  bool _isNegativeResponse(String text) {
    final lower = text.toLowerCase().trim();
    const negatives = ['no', 'nope', 'nah', 'not now', 'no thanks', 'no thank you', 'not right now', 'maybe later', 'later'];
    return negatives.any((n) => lower == n || lower.startsWith('$n ') || lower.startsWith('$n,'));
  }

  /// Handle fast decline of report check-in - exit immediately without LLM
  Future<void> _handleReportDecline() async {
    debugPrint('VoiceProvider: Fast exit from report check-in');

    // Stop any ongoing pipeline activity
    await _pipeline.stopContinuousMode();

    // Clear report mode state
    _isAwaitingReportCheckIn = false;
    exitReportMode();

    // Go to paused state
    transitionTo(VoiceState.paused);
  }

  /// Update the pipeline's alternative LLM handler based on OpenClaw state
  void _updateOpenClawHandler() {
    // TODO: OpenClaw integration disabled until properly set up
    // Always use the default LLM handler for now
    _pipeline.alternativeLLMHandler = null;
    debugPrint('VoiceProvider: OpenClaw disabled - using default LLM');
  }

  /// Handle message via OpenClaw
  /// Sends message to Bubble, which has its own tools/skills configured server-side.
  /// Bubble returns tool_use items that we execute locally on the tablet.
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
        // OpenClaw failed - speak error via TTS
        final errorMessage = "I'm having trouble connecting. You may need to check your Brain settings.";
        debugPrint('VoiceProvider: OpenClaw error - ${_openClawProvider!.error}');
        return errorMessage;
      }

      // Process any tool calls from OpenClaw/Bubble
      if (response.hasToolCalls) {
        debugPrint('VoiceProvider: Processing ${response.toolCalls.length} tool call(s) from OpenClaw');

        String? lastToolMessage;
        for (final toolCall in response.toolCalls) {
          debugPrint('VoiceProvider: Executing tool: ${toolCall.name}');

          // Convert OpenClawToolCall to ToolCall format expected by handler
          final internalToolCall = ToolCall(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.input,
          );

          final result = await _noteToolsHandler.executeTool(internalToolCall);
          debugPrint('VoiceProvider: Tool result: ${result.success} - ${result.message}');

          lastToolMessage = result.message;
        }

        // Return text response if present, otherwise last tool message
        if (response.hasText) {
          return response.text;
        } else if (lastToolMessage != null) {
          return lastToolMessage;
        }
      }

      // Just text response, no tools
      return response.text;
    } catch (e) {
      debugPrint('VoiceProvider: OpenClaw exception - $e');
      return "I'm having trouble connecting. You may need to check your Brain settings.";
    }
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

  /// Callback for navigating to reports page
  VoidCallback? onNavigateToReports;

  /// Callback for opening and playing a specific report (triggered by AI)
  void Function(String reportId)? onOpenAndPlayReport;

  /// Callback for changing report filter (Live, History, Saved)
  void Function(String filter)? onSetReportFilter;

  /// Callback for changing report category (All, Technology, etc.)
  void Function(String? category)? onSetReportCategory;

  /// Setup the game controller with pipeline integration
  void _setupGameController() {
    // Wire TTS callback
    _gameController.onPlayTTS = (text) async {
      final voice = _pendingVoice ?? 'alloy';
      await _pipeline.playTTSForLesson(text, voice);
    };

    // Wire audio file playback callback (for cached TTS)
    _gameController.onPlayAudioFile = (filePath) async {
      await _pipeline.playAudioFileForLesson(filePath);
    };

    // Update game controller with current voice
    _gameController.setTTSVoice(_pendingVoice ?? 'alloy');

    // Wire stop TTS callback (force stop audio playback)
    _gameController.onStopTTS = () async {
      await _pipeline.forceStopAudio();
    };

    // Wire spelling TTS callback (letter-by-letter with caching)
    _gameController.onPlaySpellingTTS = (word) async {
      final voice = _pendingVoice ?? 'alloy';
      const model = 'tts-1'; // Could be made configurable
      debugPrint('VoiceProvider: Playing spelling TTS for "$word"');
      await _spellingTtsPlayer.playIncorrectSpelling(
        word: word,
        voice: voice,
        model: model,
      );
      // Notify game controller that TTS is complete
      final sessionId = _gameController.sessionId;
      debugPrint('VoiceProvider: Spelling TTS complete, notifying game controller');
      _gameController.onTTSFinished(sessionId: sessionId);
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
      // Disable OpenClaw during games - games always use standard AI
      _updateOpenClawHandler();
      onNavigateToGame?.call();
      notifyListeners();
    };

    _gameController.onLessonEnded = () {
      // Resume to paused state after lesson ends
      transitionTo(VoiceState.paused);
      // Re-enable OpenClaw if it was enabled
      _updateOpenClawHandler();
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
    // Always force stop all audio first (even if game state is unexpected)
    await _pipeline.forceStopAudio();
    await _spellingTtsPlayer.stop();

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

      // FAST EXIT: Only for the initial "Is now a good time?" check-in question
      if (_isAwaitingReportCheckIn && _isNegativeResponse(transcription)) {
        debugPrint('VoiceProvider: Report check-in declined, fast exit');
        _handleReportDecline();
        return;
      }

      // Clear the check-in flag after first response (yes or other)
      if (_isAwaitingReportCheckIn) {
        _isAwaitingReportCheckIn = false;
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

      // Check for navigate to reports command from AI
      if (response.contains('[OPEN_REPORTS]') && onNavigateToReports != null) {
        debugPrint('VoiceProvider: AI requested to open reports page');
        // Navigate to reports page and trigger check-in
        onNavigateToReports!();
        // Trigger the report check-in after a short delay for navigation
        // skipIntro: true because we're already in a voice conversation
        Future.delayed(const Duration(milliseconds: 300), () {
          triggerReportCheckIn(skipIntro: true);
        });
        return;
      }

      // Check for report open command from AI
      final openReportMatch = RegExp(r'\[OPEN_REPORT:([^\]]+)\]').firstMatch(response);
      if (openReportMatch != null && _isInReportMode) {
        final reportId = openReportMatch.group(1);
        if (reportId != null && onOpenAndPlayReport != null) {
          debugPrint('VoiceProvider: AI requested to open report: $reportId');
          // Don't add this marker to conversation - just trigger the action
          onOpenAndPlayReport!(reportId);
          // Exit report mode since we're navigating
          exitReportMode();
          return;
        }
      }

      // Check for report filter change command from AI
      final filterMatch = RegExp(r'\[SET_REPORT_FILTER:(\w+)\]').firstMatch(response);
      if (filterMatch != null && onSetReportFilter != null) {
        final filter = filterMatch.group(1)!;
        debugPrint('VoiceProvider: AI requested to set report filter: $filter');
        onSetReportFilter!(filter);
        // Clean the marker from response before speaking
        response = response.replaceAll(filterMatch.group(0)!, '').trim();
      }

      // Check for report category change command from AI
      final categoryMatch = RegExp(r'\[SET_REPORT_CATEGORY:([^\]]*)\]').firstMatch(response);
      if (categoryMatch != null && onSetReportCategory != null) {
        final category = categoryMatch.group(1);
        debugPrint('VoiceProvider: AI requested to set report category: $category');
        // Empty string means "All" (null category)
        onSetReportCategory!(category?.isEmpty == true ? null : category);
        // Clean the marker from response before speaking
        response = response.replaceAll(categoryMatch.group(0)!, '').trim();
      }

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

    // Update game controller with voice for audio caching
    if (voice != null) {
      _gameController.setTTSVoice(voice);
    }
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

    // Exit report mode when pausing
    exitReportMode();

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
  
  /// End session completely - shuts down all AI services and clears context
  Future<void> endSession() async {
    debugPrint('VoiceProvider: endSession - shutting down all AI services');

    // Force stop all audio immediately
    await _pipeline.forceStopAudio();
    await _spellingTtsPlayer.stop();

    // Stop continuous mode (recording, wake word, timers)
    await _pipeline.stopContinuousMode();

    // Force exit game controller if active
    if (_gameController.isActive || _gameController.isSelected) {
      _gameController.forceExit();
    }

    // Wait for cleanup
    await Future.delayed(const Duration(milliseconds: 300));

    // Clear all state
    _conversation = null;
    _state = VoiceState.sleep;
    _isWakeWordActive = false;
    _lastTranscription = null;
    _lastResponse = null;
    _error = null;

    // Exit report mode
    _isInReportMode = false;

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

