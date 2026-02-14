import 'package:flutter/foundation.dart';
import 'lesson_phase.dart';
import 'lesson_item.dart';
import '../services/game_questions_service.dart';

/// Callback type for TTS playback
typedef TTSCallback = Future<void> Function(String text);

/// Callback type for mic control
typedef MicStartCallback = Future<void> Function();
typedef MicStopCallback = Future<void> Function();

/// GameController - Deterministic FSM for lesson/game mode
///
/// Owns all state transitions, TTS playback requests, mic control, and answer evaluation.
/// The LLM only detects intent and triggers start/exit - this controller handles everything else.
class GameController extends ChangeNotifier {
  LessonState _state = LessonState.idle;

  /// Session ID to guard against stale callbacks
  /// Incremented on startMode/exitMode to invalidate pending callbacks
  int _sessionId = 0;

  /// Tracks item IDs we've already asked to prevent repeats within session
  final Set<String> _askedItemIds = {};

  /// Flag to indicate we're in the process of exiting (ignore callbacks)
  bool _isExiting = false;

  /// Flag to track if mic is actually recording
  bool _isMicActive = false;

  /// Callbacks for TTS and mic control (wired from VoiceProvider/Pipeline)
  TTSCallback? onPlayTTS;
  MicStartCallback? onStartMic;
  MicStopCallback? onStopMic;

  /// Callback when lesson mode starts (for navigation)
  VoidCallback? onLessonStarted;

  /// Callback when lesson mode ends (for navigation)
  VoidCallback? onLessonEnded;

  /// Current state (immutable, exposed for UI)
  LessonState get state => _state;

  /// Whether lesson mode is active
  bool get isActive => _state.isActive;

  /// Current phase
  LessonPhase get phase => _state.phase;

  /// Whether mic is actually active (for UI indicator)
  bool get isMicActive => _isMicActive && _state.phase == LessonPhase.listen;

  /// Current session ID (for callback validation)
  int get sessionId => _sessionId;

  // ============================================================
  // HARDCODED ITEMS FOR INITIAL TESTING (Phase 1)
  // These will be replaced with database queries in Phase 5
  // ============================================================
  static const List<Map<String, dynamic>> _hardcodedRiddles = [
    {
      'id': 'riddle_1',
      'type': 'riddle',
      'prompt': 'I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?',
      'answer': 'a map',
      'aliases': ['map'],
    },
    {
      'id': 'riddle_2',
      'type': 'riddle',
      'prompt': 'What has hands but can\'t clap?',
      'answer': 'a clock',
      'aliases': ['clock', 'watch'],
    },
    {
      'id': 'riddle_3',
      'type': 'riddle',
      'prompt': 'The more you take, the more you leave behind. What am I?',
      'answer': 'footsteps',
      'aliases': ['footstep', 'steps', 'step'],
    },
    {
      'id': 'riddle_4',
      'type': 'riddle',
      'prompt': 'What can travel around the world while staying in a corner?',
      'answer': 'a stamp',
      'aliases': ['stamp', 'postage stamp'],
    },
    {
      'id': 'riddle_5',
      'type': 'riddle',
      'prompt': 'I speak without a mouth and hear without ears. I have no body, but I come alive with the wind. What am I?',
      'answer': 'an echo',
      'aliases': ['echo'],
    },
  ];

  // ============================================================
  // ROUTER COMMANDS (called from VoiceProvider/NoteToolsHandler)
  // ============================================================

  /// Start lesson mode with a category
  /// Called when LLM detects "let's play riddles" intent
  Future<void> startMode(String category) async {
    if (_state.isActive) {
      debugPrint('GameController: Already in lesson mode, ignoring startMode');
      return;
    }

    debugPrint('GameController: Starting lesson mode with category: $category');

    // Increment session ID to invalidate any stale callbacks
    _sessionId++;
    final currentSession = _sessionId;

    // Reset tracking
    _askedItemIds.clear();
    _isExiting = false;
    _isMicActive = false;

    // Transition to INTRO phase
    _state = LessonState(
      phase: LessonPhase.intro,
      category: category,
      questionCount: 0,
      correctCount: 0,
    );
    notifyListeners();

    // Notify that lesson mode started
    onLessonStarted?.call();

    // Play intro message
    final introText = _getIntroText(category);
    await _playTTSAndWait(introText, currentSession);

    // After intro TTS completes, onTTSFinished will be called
  }

  /// Exit lesson mode - SAFE FROM ANY PHASE
  /// Called when LLM detects "stop the game" intent or user wants to quit
  Future<void> exitMode() async {
    if (!_state.isActive && !_isExiting) {
      debugPrint('GameController: Not in lesson mode, ignoring exitMode');
      return;
    }

    // Prevent re-entry
    if (_isExiting) {
      debugPrint('GameController: Already exiting, ignoring exitMode');
      return;
    }

    debugPrint('GameController: Exiting lesson mode from phase ${_state.phase}');

    // Set exiting flag to ignore subsequent callbacks
    _isExiting = true;

    // Increment session ID to invalidate any pending callbacks
    _sessionId++;
    final currentSession = _sessionId;

    // Stop mic if it's on (safe to call even if not recording)
    if (_isMicActive) {
      _isMicActive = false;
      try {
        await onStopMic?.call();
      } catch (e) {
        debugPrint('GameController: Error stopping mic during exit: $e');
      }
    }

    // Transition to EXITING phase
    _state = _state.copyWith(phase: LessonPhase.exiting);
    notifyListeners();

    // Play exit message
    final exitText = _getExitText();
    await _playTTSAndWait(exitText, currentSession);

    // Transition to IDLE (even if TTS failed or was cancelled)
    _forceTransitionToIdle();
  }

  /// Force immediate exit without TTS (for emergency/cleanup)
  void forceExit() {
    debugPrint('GameController: Force exiting lesson mode');

    _isExiting = true;
    _sessionId++;
    _isMicActive = false;

    // Stop mic synchronously (fire and forget)
    onStopMic?.call();

    // Immediately transition to idle
    _forceTransitionToIdle();
  }

  // ============================================================
  // EVENT HANDLERS (wired from pipeline callbacks)
  // ============================================================

  /// Called when TTS playback completes
  /// This is the main FSM driver - transitions happen based on current phase
  /// sessionId parameter validates callback is for current session
  void onTTSFinished({int? sessionId}) {
    // Validate session ID if provided
    if (sessionId != null && sessionId != _sessionId) {
      debugPrint('GameController: Ignoring stale TTS callback (session $sessionId != current $_sessionId)');
      return;
    }

    // Ignore if we're exiting
    if (_isExiting) {
      debugPrint('GameController: Ignoring TTS callback during exit');
      return;
    }

    debugPrint('GameController: onTTSFinished in phase ${_state.phase}');

    switch (_state.phase) {
      case LessonPhase.intro:
        // After intro, fetch and ask first question
        _fetchAndAskNextQuestion();
        break;

      case LessonPhase.ask:
        // After asking question, start listening
        _transitionToListen();
        break;

      case LessonPhase.feedback:
        // After feedback, fetch and ask next question
        _fetchAndAskNextQuestion();
        break;

      case LessonPhase.exiting:
        // After exit message, go to idle
        _forceTransitionToIdle();
        break;

      case LessonPhase.idle:
      case LessonPhase.listen:
      case LessonPhase.eval:
        // No action needed for these phases
        break;
    }
  }

  /// Called when ASR produces a transcription result
  /// Only processes if in LISTEN phase and session is valid
  void onASRResult(String transcription, {int? sessionId}) {
    // Validate session ID if provided
    if (sessionId != null && sessionId != _sessionId) {
      debugPrint('GameController: Ignoring stale ASR callback (session $sessionId != current $_sessionId)');
      return;
    }

    // Ignore if we're exiting
    if (_isExiting) {
      debugPrint('GameController: Ignoring ASR callback during exit');
      return;
    }

    if (_state.phase != LessonPhase.listen) {
      debugPrint('GameController: Ignoring ASR result - not in LISTEN phase (current: ${_state.phase})');
      return;
    }

    debugPrint('GameController: onASRResult in LISTEN phase: "$transcription"');

    // Mark mic as inactive
    _isMicActive = false;

    // Store the user's answer
    _state = _state.copyWith(
      phase: LessonPhase.eval,
      userAnswer: transcription,
    );
    notifyListeners();

    // Stop mic
    onStopMic?.call();

    // Evaluate the answer
    _evaluateAnswer(transcription);
  }

  /// Notify that mic recording has started (for UI indicator)
  void onMicStarted() {
    _isMicActive = true;
    notifyListeners();
  }

  /// Notify that mic recording has stopped (for UI indicator)
  void onMicStopped() {
    _isMicActive = false;
    notifyListeners();
  }

  // ============================================================
  // INTERNAL FSM TRANSITIONS
  // ============================================================

  /// Transition to LISTEN phase (mic on)
  Future<void> _transitionToListen() async {
    if (_isExiting) return;

    debugPrint('FSM: _transitionToListen ENTER (phase=${_state.phase}, session=$_sessionId)');

    _state = _state.copyWith(phase: LessonPhase.listen);
    notifyListeners();

    debugPrint('FSM: calling onStartMic (session=$_sessionId, callback=${onStartMic != null})');

    // Start mic and track state
    _isMicActive = true;
    await onStartMic?.call();

    debugPrint('FSM: onStartMic returned (session=$_sessionId)');
  }

  /// Force transition to IDLE phase (used during exit)
  void _forceTransitionToIdle() {
    debugPrint('GameController: Force transitioning to IDLE phase');

    _state = LessonState.idle;
    _askedItemIds.clear();
    _isExiting = false;
    _isMicActive = false;
    notifyListeners();

    // Notify that lesson mode ended
    onLessonEnded?.call();
  }

  /// Fetch next item and transition to ASK phase
  Future<void> _fetchAndAskNextQuestion() async {
    if (_isExiting) return;

    final currentSession = _sessionId;
    debugPrint('GameController: Fetching next question for category ${_state.category}');

    final item = await _getNextItem(_state.category);

    // Check if we exited during fetch
    if (_isExiting || _sessionId != currentSession) {
      debugPrint('GameController: Session changed during fetch, aborting');
      return;
    }

    if (item == null) {
      debugPrint('GameController: No more questions available');
      // Play "no more questions" message and exit
      _state = _state.copyWith(phase: LessonPhase.feedback);
      notifyListeners();
      await _playTTSAndWait('No more questions available. Thanks for playing!', currentSession);

      // Check again after TTS
      if (!_isExiting && _sessionId == currentSession) {
        _forceTransitionToIdle();
      }
      return;
    }

    // Track that we've asked this item
    _askedItemIds.add(item.id);

    // Transition to ASK phase with new item
    _state = _state.copyWith(
      phase: LessonPhase.ask,
      currentItem: item,
      questionCount: _state.questionCount + 1,
      clearUserAnswer: true,
      clearIsCorrect: true,
    );
    notifyListeners();

    // Play the question
    await _playTTSAndWait(item.prompt, currentSession);

    // onTTSFinished will handle the transition to LISTEN
  }

  /// Evaluate the user's answer and provide feedback
  Future<void> _evaluateAnswer(String userAnswer) async {
    if (_isExiting) return;

    final currentSession = _sessionId;
    final currentItem = _state.currentItem;

    if (currentItem == null) {
      debugPrint('GameController: No current item to evaluate');
      return;
    }

    // Deterministic answer check
    final isCorrect = currentItem.checkAnswer(userAnswer);

    debugPrint('GameController: Answer "$userAnswer" is ${isCorrect ? "CORRECT" : "INCORRECT"} (expected: ${currentItem.answer})');

    // Update state with result
    _state = _state.copyWith(
      phase: LessonPhase.feedback,
      isCorrect: isCorrect,
      correctCount: isCorrect ? _state.correctCount + 1 : _state.correctCount,
    );
    notifyListeners();

    // Play feedback
    final feedbackText = isCorrect
        ? _getCorrectFeedback()
        : _getIncorrectFeedback(currentItem.answer);

    await _playTTSAndWait(feedbackText, currentSession);

    // onTTSFinished will handle the transition to next question
  }

  // ============================================================
  // ITEM FETCHING
  // ============================================================

  /// Get next item for the category
  /// Uses hardcoded items for now, will switch to database later
  Future<LessonItem?> _getNextItem(String category) async {
    // First try to get from database
    final dbQuestion = await GameQuestionsService.getNextQuestion(
      category == 'random' ? 'random' : category,
    );

    if (dbQuestion != null && !_askedItemIds.contains(dbQuestion.id)) {
      // Mark as used in database
      await GameQuestionsService.markAsUsed(dbQuestion.id);

      return LessonItem(
        id: dbQuestion.id,
        type: dbQuestion.category,
        prompt: dbQuestion.question,
        answer: dbQuestion.answer,
      );
    }

    // Fallback to hardcoded items if database is empty or all used
    debugPrint('GameController: Falling back to hardcoded items');
    for (final itemData in _hardcodedRiddles) {
      final id = itemData['id'] as String;
      if (!_askedItemIds.contains(id)) {
        return LessonItem.fromMap(itemData);
      }
    }

    // No more items available
    return null;
  }

  // ============================================================
  // TEXT GENERATION HELPERS
  // ============================================================

  String _getIntroText(String category) {
    switch (category.toLowerCase()) {
      case 'riddle':
      case 'riddles':
        return "Let's do some riddles! I'll ask you a riddle and you try to guess the answer.";
      case 'joke':
      case 'jokes':
        return "Let's have some laughs! I'll tell you a joke.";
      case 'trivia':
        return "Let's test your knowledge! I'll ask you some trivia questions.";
      default:
        return "Let's play! I'll ask you some questions.";
    }
  }

  String _getExitText() {
    final correct = _state.correctCount;
    final total = _state.questionCount;

    if (total == 0) {
      return "Thanks for playing!";
    }

    if (correct == total) {
      return "Amazing! You got all $total questions right! Thanks for playing!";
    } else if (correct > total / 2) {
      return "Great job! You got $correct out of $total. Thanks for playing!";
    } else {
      return "You got $correct out of $total. Better luck next time! Thanks for playing!";
    }
  }

  String _getCorrectFeedback() {
    // Vary the feedback to keep it interesting
    final variations = [
      "That's right!",
      "Correct!",
      "You got it!",
      "Exactly!",
      "Well done!",
    ];
    return variations[_state.questionCount % variations.length];
  }

  String _getIncorrectFeedback(String correctAnswer) {
    return "The answer is: $correctAnswer.";
  }

  // ============================================================
  // TTS HELPER
  // ============================================================

  /// Play TTS and wait for completion
  /// The actual waiting happens via onTTSFinished callback
  Future<void> _playTTSAndWait(String text, int sessionId) async {
    // Check if session is still valid
    if (_sessionId != sessionId || _isExiting) {
      debugPrint('GameController: Session changed, skipping TTS');
      return;
    }

    if (onPlayTTS == null) {
      debugPrint('GameController: No TTS callback configured, skipping TTS');
      // Simulate immediate completion if no TTS
      Future.microtask(() => onTTSFinished(sessionId: sessionId));
      return;
    }

    debugPrint('GameController: Playing TTS: "$text"');
    await onPlayTTS!(text);
    // Note: onTTSFinished will be called when playback actually completes
  }

  // ============================================================
  // MANUAL CONTROLS (for UI buttons)
  // ============================================================

  /// Skip current question and move to next
  Future<void> skipQuestion() async {
    if (!_state.isActive || _state.phase == LessonPhase.idle || _isExiting) {
      return;
    }

    final currentSession = _sessionId;

    // Stop mic if listening
    if (_state.phase == LessonPhase.listen) {
      _isMicActive = false;
      await onStopMic?.call();
    }

    // Reveal answer and move on
    if (_state.currentItem != null) {
      _state = _state.copyWith(
        phase: LessonPhase.feedback,
        isCorrect: false,
      );
      notifyListeners();

      await _playTTSAndWait(_getIncorrectFeedback(_state.currentItem!.answer), currentSession);
    } else {
      _fetchAndAskNextQuestion();
    }
  }

  /// Repeat current question
  Future<void> repeatQuestion() async {
    if (!_state.isActive || _state.currentItem == null || _isExiting) {
      return;
    }

    final currentSession = _sessionId;

    // Stop mic if listening
    if (_state.phase == LessonPhase.listen) {
      _isMicActive = false;
      await onStopMic?.call();
    }

    // Go back to ASK phase and replay
    _state = _state.copyWith(phase: LessonPhase.ask);
    notifyListeners();

    await _playTTSAndWait(_state.currentItem!.prompt, currentSession);
  }

  @override
  void dispose() {
    _askedItemIds.clear();
    _isExiting = true;
    super.dispose();
  }
}
