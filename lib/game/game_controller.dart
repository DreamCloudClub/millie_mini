import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'lesson_phase.dart';
import 'lesson_item.dart';
import '../services/trivia_service.dart';
import '../services/riddles_service.dart';
import '../services/jokes_service.dart';
import '../services/true_false_service.dart';
import '../services/spelling_words_service.dart';
import '../services/math_problem_service.dart';
import '../services/letters_service.dart';
import '../services/numbers_service.dart';
import '../services/shapes_service.dart';
import '../services/animals_service.dart';
import '../services/foods_service.dart';
import '../services/geography_service.dart';
import '../providers/custom_quiz_provider.dart';

/// Callback type for TTS playback
typedef TTSCallback = Future<void> Function(String text);

/// Callback type for spelling TTS (letter-by-letter with caching)
typedef SpellingTTSCallback = Future<void> Function(String word);

/// Callback type for playing audio files (cached TTS)
typedef AudioFileCallback = Future<void> Function(String filePath);

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

  /// Flag to track if game is paused
  bool _isPaused = false;

  /// Store the phase we were in when paused (to resume correctly)
  LessonPhase? _pausedFromPhase;

  /// Timer fields for countdown functionality
  int? _timeLimitSeconds;
  int? _remainingSeconds;
  Timer? _countdownTimer;

  /// Difficulty filter for questions
  String? _difficultyFilter;

  /// Auto-record setting (when false, user must press Record to answer)
  bool _autoRecord = true;

  /// Reference to CustomQuizProvider for resolving custom quiz categories
  CustomQuizProvider? _customQuizProvider;

  /// Callbacks for TTS and mic control (wired from VoiceProvider/Pipeline)
  TTSCallback? onPlayTTS;
  SpellingTTSCallback? onPlaySpellingTTS;
  AudioFileCallback? onPlayAudioFile;
  MicStartCallback? onStartMic;
  MicStopCallback? onStopMic;
  MicStopCallback? onStopTTS; // Stops audio playback immediately

  /// Current TTS voice (for caching audio)
  String _ttsVoice = 'nova';

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

  /// Whether game is paused
  bool get isPaused => _isPaused;

  /// Whether pause is currently allowed (quizzes: only in LISTEN, lessons: anytime)
  bool get canPause {
    if (!_state.isGameRunning || _isPaused || _isExiting) return false;
    final isLesson = _state.currentItem?.gradingType == GradingType.none;
    return isLesson || _state.phase == LessonPhase.listen;
  }

  /// Whether a category is selected and ready to start
  bool get isSelected => _state.phase == LessonPhase.selected;

  /// Whether the game is actively running (past selected phase)
  bool get isGameRunning => _state.isGameRunning;

  /// Current session ID (for callback validation)
  int get sessionId => _sessionId;

  /// Remaining seconds on the countdown timer (null when no timer active)
  int? get remainingSeconds => _remainingSeconds;

  /// Whether the timer is active
  bool get isTimerActive => _countdownTimer != null && _countdownTimer!.isActive;

  /// Current time limit setting in seconds
  int? get timeLimitSeconds => _timeLimitSeconds;

  /// Current difficulty filter
  String? get difficultyFilter => _difficultyFilter;

  /// Whether auto-record is enabled
  bool get autoRecord => _autoRecord;

  // ============================================================
  // SETTINGS CONFIGURATION
  // ============================================================

  /// Set the time limit for listening phase (null = no limit)
  void setTimeLimit(int? seconds) {
    _timeLimitSeconds = seconds;
    debugPrint('GameController: Time limit set to $seconds seconds');
  }

  /// Set the difficulty filter for questions
  void setDifficulty(String? difficulty) {
    _difficultyFilter = difficulty;
    debugPrint('GameController: Difficulty filter set to $difficulty');
  }

  /// Set the auto-record setting
  void setAutoRecord(bool autoRecord) {
    _autoRecord = autoRecord;
    debugPrint('GameController: Auto-record set to $autoRecord');
  }

  /// Set the TTS voice (for caching audio)
  void setTTSVoice(String voice) {
    _ttsVoice = voice;
    debugPrint('GameController: TTS voice set to $voice');
  }

  /// Set the CustomQuizProvider reference
  void setCustomQuizProvider(CustomQuizProvider provider) {
    _customQuizProvider = provider;
    debugPrint('GameController: CustomQuizProvider set');
  }

  /// Cancel any active countdown timer
  void _cancelTimer() {
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
      _remainingSeconds = null;
      debugPrint('GameController: Timer cancelled');
    }
  }

  /// Start the countdown timer (visible, for auto-record mode)
  void _startTimer() {
    if (_timeLimitSeconds == null || _timeLimitSeconds! <= 0) {
      return;
    }

    // Cancel any existing timer first
    _cancelTimer();

    _remainingSeconds = _timeLimitSeconds;
    debugPrint('GameController: Starting timer with $_remainingSeconds seconds');
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds == null || _remainingSeconds! <= 0) {
        _handleTimerExpired();
        return;
      }

      _remainingSeconds = _remainingSeconds! - 1;
      notifyListeners();

      if (_remainingSeconds! <= 0) {
        _handleTimerExpired();
      }
    });
  }

  /// Start a silent safety timeout (30 seconds max, for manual record mode)
  /// No visible countdown - just a safety limit
  void _startSafetyTimeout() {
    debugPrint('GameController: Starting 30-second safety timeout (no visible countdown)');
    // Don't set _remainingSeconds - this keeps the UI from showing a countdown
    _countdownTimer = Timer(const Duration(seconds: 30), () {
      debugPrint('GameController: Safety timeout expired');
      _handleTimerExpired();
    });
  }

  /// Handle timer expiration - stop mic and treat as empty answer
  Future<void> _handleTimerExpired() async {
    // Guard against multiple calls
    if (_countdownTimer == null) return;

    debugPrint('GameController: Timer expired - treating as timeout');
    _cancelTimer();

    // Only handle if we're still in listen phase
    if (_state.phase != LessonPhase.listen || _isExiting || _isPaused) {
      return;
    }

    // Mark mic as inactive
    _isMicActive = false;

    // Stop mic
    await onStopMic?.call();

    // Treat as empty answer (skipped)
    _state = _state.copyWith(
      phase: LessonPhase.eval,
      userAnswer: '',
    );
    notifyListeners();

    // Evaluate as incorrect (empty answer)
    _evaluateAnswer('');
  }

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

  /// Select a category without starting the game
  /// User must press Start to begin
  void selectCategory(String category) {
    debugPrint('GameController: Category selected: $category');

    // Reset tracking
    _askedItemIds.clear();
    _isExiting = false;
    _isMicActive = false;
    _isPaused = false;
    _pausedFromPhase = null;

    // Transition to SELECTED phase
    _state = LessonState(
      phase: LessonPhase.selected,
      category: category,
      questionCount: 0,
      correctCount: 0,
    );
    notifyListeners();
  }

  /// Start the game (from selected state or directly with category)
  /// Called when user presses Start button
  Future<void> startMode([String? category]) async {
    // If already running, ignore
    if (_state.isGameRunning) {
      debugPrint('GameController: Game already running, ignoring startMode');
      return;
    }

    // Use provided category or the already selected one
    final gameCategory = category ?? _state.category;
    if (gameCategory.isEmpty) {
      debugPrint('GameController: No category selected, ignoring startMode');
      return;
    }

    debugPrint('GameController: Starting game with category: $gameCategory');

    // Increment session ID to invalidate any stale callbacks
    _sessionId++;
    final currentSession = _sessionId;

    // Reset tracking if starting fresh (not from selected)
    if (!_state.isSelected) {
      _askedItemIds.clear();
    }
    _isExiting = false;
    _isMicActive = false;
    _isPaused = false;
    _pausedFromPhase = null;

    // Transition to INTRO phase
    _state = LessonState(
      phase: LessonPhase.intro,
      category: gameCategory,
      questionCount: 0,
      correctCount: 0,
    );
    notifyListeners();

    // Notify that lesson mode started
    onLessonStarted?.call();

    // Play intro message
    final introText = _getIntroText(gameCategory);
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

    // Cancel any active timer
    _cancelTimer();

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
    _cancelTimer();

    // Stop TTS audio immediately
    onStopTTS?.call();

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
        // For lessons (no grading), auto-advance after TTS without listening
        if (_state.currentItem?.gradingType == GradingType.none) {
          // Brief pause, then next question
          Future.delayed(const Duration(seconds: 2), () {
            if (!_isExiting && !_isPaused && _sessionId == sessionId) {
              _fetchAndAskNextQuestion();
            }
          });
          break;
        }
        // After asking question, start listening (only if auto-record is on)
        if (_autoRecord) {
          _transitionToListen();
        }
        // If auto-record is off, stay in ASK phase - user must press Record button
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
      case LessonPhase.selected:
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

    // Ignore if we're paused (mic was stopped for pause, not for answer)
    if (_isPaused) {
      debugPrint('GameController: Ignoring ASR callback - game is paused');
      return;
    }

    if (_state.phase != LessonPhase.listen) {
      debugPrint('GameController: Ignoring ASR result - not in LISTEN phase (current: ${_state.phase})');
      return;
    }

    debugPrint('GameController: onASRResult in LISTEN phase: "$transcription"');

    // Cancel timer since we got an answer
    _cancelTimer();

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

    // Start countdown timer only if auto-record is ON and time limit is set
    // When auto-record is OFF, use a silent 30-second safety timeout
    if (_autoRecord) {
      _startTimer();
    } else {
      _startSafetyTimeout();
    }

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

    // Check for cached audio (animals) - will generate and cache if not found
    if (_state.isAnimalsMode && onPlayAudioFile != null) {
      final audioPath = await AnimalsService.getAudioPath(
        animalId: item.id,
        text: item.ttsPrompt,
        voice: _ttsVoice,
      );
      if (audioPath != null) {
        debugPrint('GameController: Playing audio for ${item.answer}');
        await onPlayAudioFile!(audioPath);
        return; // onTTSFinished will be called when playback completes
      }
    }

    // Check for cached audio (foods) - will generate and cache if not found
    if (_state.isFoodsMode && onPlayAudioFile != null) {
      final audioPath = await FoodsService.getAudioPath(
        foodId: item.id,
        text: item.ttsPrompt,
        voice: _ttsVoice,
      );
      if (audioPath != null) {
        debugPrint('GameController: Playing audio for ${item.answer}');
        await onPlayAudioFile!(audioPath);
        return; // onTTSFinished will be called when playback completes
      }
    }

    // Fall back to regular TTS
    await _playTTSAndWait(item.ttsPrompt, currentSession);

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
    // For incorrect spelling answers, use special spelling TTS if available
    if (!isCorrect &&
        currentItem.gradingType == GradingType.spelling &&
        onPlaySpellingTTS != null) {
      debugPrint('GameController: Using spelling TTS for incorrect answer');
      await onPlaySpellingTTS!(currentItem.answer);
      // onTTSFinished will be called by SpellingTtsPlayer when done
    } else {
      final feedbackText = isCorrect
          ? _getCorrectFeedback()
          : _getIncorrectFeedback(currentItem.answer);
      await _playTTSAndWait(feedbackText, currentSession);
      // onTTSFinished will handle the transition to next question
    }
  }

  // ============================================================
  // ITEM FETCHING
  // ============================================================

  /// Get next item for the category
  /// Routes to appropriate service based on category
  Future<LessonItem?> _getNextItem(String category) async {
    // Custom quiz: picks a random category from the quiz's category list
    if (category.startsWith('custom:')) {
      return _getNextFromCustomQuiz(category.substring(7)); // Remove 'custom:' prefix
    }

    // Random: pick from ALL categories including spelling and math
    if (category == 'random') {
      return _getNextRandomItem();
    }

    // Math uses procedural generation (supports math:operation format)
    if (category == 'math' || category.startsWith('math:')) {
      return _getNextMathProblem(category);
    }

    // Letters uses procedural generation (supports letters:mode format)
    if (category == 'letters' || category.startsWith('letters:')) {
      return _getNextLetter(category);
    }

    // Numbers uses procedural generation with difficulty
    if (category == 'numbers') {
      return _getNextNumber();
    }

    // Shapes uses procedural generation
    if (category == 'shapes') {
      return _getNextShape();
    }

    // Animals quiz uses database
    if (category == 'animals' || category == 'animals:quiz') {
      return _getNextAnimal();
    }

    // Animals lessons uses database (auto-play, no voice input)
    if (category == 'animals:lessons') {
      return _getNextAnimalLesson();
    }

    // Animals random - mix of quiz and lessons
    if (category == 'animals:random') {
      return _getNextAnimalRandom();
    }

    // Foods quiz uses database
    if (category == 'foods' || category == 'foods:quiz') {
      return _getNextFood();
    }

    // Foods lessons uses database (auto-play, no voice input)
    if (category == 'foods:lessons') {
      return _getNextFoodLesson();
    }

    // Foods random - mix of quiz and lessons
    if (category == 'foods:random') {
      return _getNextFoodRandom();
    }

    // Geography (US States) quiz
    if (category == 'geography' || category == 'geography:quiz') {
      return _getNextGeography();
    }

    // Geography (US States) lessons (auto-play, no voice input)
    if (category == 'geography:lessons') {
      return _getNextGeographyLesson();
    }

    // Geography random - mix of quiz and lessons
    if (category == 'geography:random') {
      return _getNextGeographyRandom();
    }

    // Spelling uses its own table/service
    if (category == 'spelling') {
      return _getNextSpellingWord();
    }

    // Trivia uses trivia_questions table
    if (category == 'trivia') {
      return _getNextTriviaQuestion();
    }

    // Riddles use riddles table
    if (category == 'riddle' || category == 'riddles') {
      return _getNextRiddle();
    }

    // Jokes use jokes table
    if (category == 'joke' || category == 'jokes') {
      return _getNextJoke();
    }

    // True/False uses true_false_questions table
    if (category == 'truefalse' || category == 'true false' || category == 'true or false') {
      return _getNextTrueFalseQuestion();
    }

    // Fallback to hardcoded items for unknown categories
    debugPrint('GameController: Unknown category $category, falling back to hardcoded items');
    for (final itemData in _hardcodedRiddles) {
      final id = itemData['id'] as String;
      if (!_askedItemIds.contains(id)) {
        return LessonItem.fromMap(itemData);
      }
    }

    // No more items available
    return null;
  }

  /// Get next spelling word from spelling_words table
  Future<LessonItem?> _getNextSpellingWord() async {
    // Pass excludeIds to filter out words already asked this session
    final word = await SpellingWordsService.getNextWord(
      difficulty: _difficultyFilter,
      excludeIds: _askedItemIds,
    );

    if (word != null) {
      // Mark as used in database
      await SpellingWordsService.markAsUsed(word.id);

      return LessonItem(
        id: word.id,
        type: 'spelling',
        prompt: word.word,
        answer: word.word,
        gradingType: GradingType.spelling,
        lettersPhonetic: word.lettersPhonetic,
      );
    }

    return null;
  }

  /// Get next trivia question from trivia_questions table
  Future<LessonItem?> _getNextTriviaQuestion() async {
    final question = await TriviaService.getNextQuestion(
      difficulty: _difficultyFilter,
      excludeIds: _askedItemIds,
    );

    if (question != null) {
      await TriviaService.markAsUsed(question.id);

      return LessonItem(
        id: question.id,
        type: 'trivia',
        prompt: question.question,
        answer: question.answer,
        gradingType: GradingType.flexible,
      );
    }

    return null;
  }

  /// Get next riddle from riddles table
  Future<LessonItem?> _getNextRiddle() async {
    final riddle = await RiddlesService.getNextQuestion(
      difficulty: _difficultyFilter,
      excludeIds: _askedItemIds,
    );

    if (riddle != null) {
      await RiddlesService.markAsUsed(riddle.id);

      return LessonItem(
        id: riddle.id,
        type: 'riddle',
        prompt: riddle.question,
        answer: riddle.answer,
        gradingType: GradingType.flexible,
      );
    }

    return null;
  }

  /// Get next joke from jokes table
  Future<LessonItem?> _getNextJoke() async {
    final joke = await JokesService.getNextQuestion(
      difficulty: _difficultyFilter,
      excludeIds: _askedItemIds,
    );

    if (joke != null) {
      await JokesService.markAsUsed(joke.id);

      return LessonItem(
        id: joke.id,
        type: 'joke',
        prompt: joke.question,
        answer: joke.answer,
        gradingType: GradingType.flexible,
      );
    }

    return null;
  }

  /// Get next true/false question from true_false_questions table
  Future<LessonItem?> _getNextTrueFalseQuestion() async {
    final question = await TrueFalseService.getNextQuestion(
      difficulty: _difficultyFilter,
      excludeIds: _askedItemIds,
    );

    if (question != null) {
      await TrueFalseService.markAsUsed(question.id);

      return LessonItem(
        id: question.id,
        type: 'truefalse',
        prompt: 'True or false: ${question.statement}',
        answer: question.answerText,
        aliases: question.answer ? ['yes', 'correct', 'right'] : ['no', 'incorrect', 'wrong'],
        gradingType: GradingType.flexible,
      );
    }

    return null;
  }

  /// Get next item from a truly random mix of ALL categories
  /// Includes: riddle, joke, trivia, truefalse, spelling, math, letters
  Future<LessonItem?> _getNextRandomItem() async {
    // All available categories
    const allCategories = ['riddle', 'joke', 'trivia', 'truefalse', 'spelling', 'math', 'letters', 'shapes', 'animals'];

    // Shuffle and try each until we find one with available items
    final shuffled = List<String>.from(allCategories)..shuffle(Random());

    for (final category in shuffled) {
      LessonItem? item;

      if (category == 'spelling') {
        item = await _getNextSpellingWord();
      } else if (category == 'math') {
        item = await _getNextMathProblem('math');
      } else if (category == 'trivia') {
        item = await _getNextTriviaQuestion();
      } else if (category == 'riddle') {
        item = await _getNextRiddle();
      } else if (category == 'joke') {
        item = await _getNextJoke();
      } else if (category == 'truefalse') {
        item = await _getNextTrueFalseQuestion();
      } else if (category == 'letters') {
        item = await _getNextLetter('letters:random');
      } else if (category == 'numbers') {
        item = await _getNextNumber();
      } else if (category == 'shapes') {
        item = await _getNextShape();
      }

      if (item != null) {
        return item;
      }
    }

    return null;
  }

  /// Get next procedurally-generated math problem
  /// Category can be 'math' or 'math:operation' (e.g., 'math:addition')
  Future<LessonItem?> _getNextMathProblem(String category) async {
    // Parse operation from category (e.g., 'math:addition' -> 'addition')
    String? operation;
    if (category.contains(':')) {
      operation = category.split(':')[1];
      if (operation == 'random') operation = null; // Random = no filter
    }

    debugPrint('GameController: Generating math problem with difficulty=$_difficultyFilter, operation=$operation');

    final problem = MathProblemService.generate(
      difficulty: _difficultyFilter,
      operation: operation,
    );

    debugPrint('GameController: Generated math: ${problem.question} = ${problem.answer}');

    return LessonItem(
      id: 'math_${DateTime.now().millisecondsSinceEpoch}',
      type: 'math',
      prompt: problem.question,
      answer: problem.answer,
      gradingType: GradingType.numeric,
    );
  }

  /// Get next letter recognition problem
  /// Category can be 'letters', 'letters:uppercase', 'letters:lowercase', 'letters:random'
  Future<LessonItem?> _getNextLetter(String category) async {
    // Parse mode from category (e.g., 'letters:uppercase' -> 'uppercase')
    String mode = 'random';
    if (category.contains(':')) {
      mode = category.split(':')[1];
    }

    final problem = LettersService.generate(
      mode: mode,
      excludeIds: _askedItemIds,
    );

    if (problem == null) {
      return null; // All letters shown
    }

    return LessonItem(
      id: problem.letter, // Use the letter itself as ID for tracking
      type: 'letters',
      prompt: problem.letter,
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.flexible,
    );
  }

  /// Get next number recognition problem
  /// Uses difficulty setting: 'easy' (0-9), 'medium' (10-99), 'hard' (100-999)
  Future<LessonItem?> _getNextNumber() async {
    final problem = NumbersService.generate(
      difficulty: _difficultyFilter,
      excludeIds: _askedItemIds,
    );

    if (problem == null) {
      return null; // All numbers shown
    }

    return LessonItem(
      id: problem.number, // Use the number itself as ID for tracking
      type: 'numbers',
      prompt: problem.number,
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.flexible,
    );
  }

  /// Get next procedurally-generated shape problem
  Future<LessonItem?> _getNextShape() async {
    final problem = ShapesService.generate(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All shapes shown
    }

    return LessonItem(
      id: problem.id,
      type: 'shapes',
      prompt: problem.hint, // "This shape has 3 sides. What is it?"
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.flexible,
    );
  }

  /// Get next animal from database
  Future<LessonItem?> _getNextAnimal() async {
    final problem = await AnimalsService.generate(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All animals shown
    }

    await AnimalsService.markAsUsed(problem.id);

    return LessonItem(
      id: problem.id,
      type: 'animals',
      prompt: problem.hint, // "This is a mammal. [description] What is it called?"
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.flexible,
      cachedAudioUrl: problem.narrationAudioUrl,
      imageUrl: problem.imageUrl,
    );
  }

  /// Get next animal lesson (auto-play, no voice input)
  Future<LessonItem?> _getNextAnimalLesson() async {
    final problem = await AnimalsService.generateLesson(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All animals shown
    }

    await AnimalsService.markAsUsed(problem.id);

    return LessonItem(
      id: problem.id,
      type: 'animals:lesson',
      prompt: problem.hint, // Full narration with type included
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.none, // No grading for lessons
      cachedAudioUrl: problem.narrationAudioUrl,
      imageUrl: problem.imageUrl,
    );
  }

  /// Get next animal - randomly picks between quiz and lesson
  Future<LessonItem?> _getNextAnimalRandom() async {
    // Randomly pick between quiz (0) and lesson (1)
    final isLesson = Random().nextBool();

    if (isLesson) {
      final item = await _getNextAnimalLesson();
      if (item != null) return item;
      // Fall back to quiz if no lessons available
      return _getNextAnimal();
    } else {
      final item = await _getNextAnimal();
      if (item != null) return item;
      // Fall back to lesson if no quiz available
      return _getNextAnimalLesson();
    }
  }

  /// Get next food from database
  Future<LessonItem?> _getNextFood() async {
    final problem = await FoodsService.generate(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All foods shown
    }

    await FoodsService.markAsUsed(problem.id);

    return LessonItem(
      id: problem.id,
      type: 'foods',
      prompt: problem.hint, // "This is a fruit. [description] What is it called?"
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.flexible,
      cachedAudioUrl: problem.narrationAudioUrl,
      imageUrl: problem.imageUrl,
    );
  }

  /// Get next food lesson (auto-play, no voice input)
  Future<LessonItem?> _getNextFoodLesson() async {
    final problem = await FoodsService.generateLesson(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All foods shown
    }

    await FoodsService.markAsUsed(problem.id);

    return LessonItem(
      id: problem.id,
      type: 'foods:lesson',
      prompt: problem.hint, // Full narration with category included
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.none, // No grading for lessons
      cachedAudioUrl: problem.narrationAudioUrl,
      imageUrl: problem.imageUrl,
    );
  }

  /// Get next food - randomly picks between quiz and lesson
  Future<LessonItem?> _getNextFoodRandom() async {
    // Randomly pick between quiz (0) and lesson (1)
    final isLesson = Random().nextBool();

    if (isLesson) {
      final item = await _getNextFoodLesson();
      if (item != null) return item;
      // Fall back to quiz if no lessons available
      return _getNextFood();
    } else {
      final item = await _getNextFood();
      if (item != null) return item;
      // Fall back to lesson if no quiz available
      return _getNextFoodLesson();
    }
  }

  /// Get next geography (US state) quiz from local JSON
  Future<LessonItem?> _getNextGeography() async {
    final problem = await GeographyService.generate(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All states shown
    }

    await GeographyService.markAsUsed(problem.id);

    return LessonItem(
      id: problem.id,
      type: 'geography',
      prompt: problem.hint, // Quiz hint without revealing the name
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.flexible,
      stateId: problem.stateId,
      stateCapital: problem.capital,
      stateRegion: problem.region,
    );
  }

  /// Get next geography lesson (auto-play, no voice input)
  Future<LessonItem?> _getNextGeographyLesson() async {
    final problem = await GeographyService.generateLesson(excludeIds: _askedItemIds);

    if (problem == null) {
      return null; // All states shown
    }

    await GeographyService.markAsUsed(problem.id);

    return LessonItem(
      id: problem.id,
      type: 'geography:lesson',
      prompt: problem.hint, // Full narration with "Can you say [state]?"
      answer: problem.answer,
      aliases: problem.aliases,
      gradingType: GradingType.none, // No grading for lessons
      stateId: problem.stateId,
      stateCapital: problem.capital,
      stateRegion: problem.region,
    );
  }

  /// Get next geography - randomly picks between quiz and lesson
  Future<LessonItem?> _getNextGeographyRandom() async {
    // Randomly pick between quiz (0) and lesson (1)
    final isLesson = Random().nextBool();

    if (isLesson) {
      final item = await _getNextGeographyLesson();
      if (item != null) return item;
      // Fall back to quiz if no lessons available
      return _getNextGeography();
    } else {
      final item = await _getNextGeography();
      if (item != null) return item;
      // Fall back to lesson if no quiz available
      return _getNextGeographyLesson();
    }
  }

  /// Get next item from a custom quiz (randomly picks from its categories)
  /// Shuffles categories and tries each until one returns an item
  Future<LessonItem?> _getNextFromCustomQuiz(String quizId) async {
    if (_customQuizProvider == null) {
      debugPrint('GameController: No CustomQuizProvider set');
      return null;
    }

    final quiz = _customQuizProvider!.getQuizById(quizId);
    if (quiz == null || quiz.categories.isEmpty) {
      debugPrint('GameController: Quiz not found or has no categories: $quizId');
      return null;
    }

    // Shuffle categories and try each until we find one with available items
    final shuffled = List<String>.from(quiz.categories)..shuffle(Random());
    debugPrint('GameController: Custom quiz "$quizId" trying categories: $shuffled');

    for (final category in shuffled) {
      LessonItem? item;

      if (category == 'spelling') {
        item = await _getNextSpellingWord();
      } else if (category == 'math' || category.startsWith('math:')) {
        item = await _getNextMathProblem(category);
      } else if (category == 'letters' || category.startsWith('letters:')) {
        item = await _getNextLetter(category);
      } else if (category == 'numbers') {
        item = await _getNextNumber();
      } else if (category == 'trivia') {
        item = await _getNextTriviaQuestion();
      } else if (category == 'riddle' || category == 'riddles') {
        item = await _getNextRiddle();
      } else if (category == 'joke' || category == 'jokes') {
        item = await _getNextJoke();
      } else if (category == 'truefalse' || category == 'true false' || category == 'true or false') {
        item = await _getNextTrueFalseQuestion();
      } else if (category == 'shapes') {
        item = await _getNextShape();
      } else if (category == 'animals' || category == 'animals:quiz') {
        item = await _getNextAnimal();
      } else if (category == 'geography' || category == 'geography:quiz') {
        item = await _getNextGeography();
      }

      if (item != null) {
        debugPrint('GameController: Custom quiz got item from category: $category');
        return item;
      }
    }

    debugPrint('GameController: Custom quiz exhausted all categories');
    return null;
  }

  // ============================================================
  // TEXT GENERATION HELPERS
  // ============================================================

  String _getIntroText(String category) {
    // Handle custom quiz
    if (category.startsWith('custom:')) {
      final quizId = category.substring(7);
      final quiz = _customQuizProvider?.getQuizById(quizId);
      if (quiz != null) {
        return "Let's play ${quiz.name}! I'll mix in some ${quiz.categoriesDisplay.toLowerCase()}.";
      }
      return "Let's play! I'll ask you some questions.";
    }

    switch (category.toLowerCase()) {
      case 'riddle':
      case 'riddles':
        return "Let's do some riddles! I'll ask you a riddle and you try to guess the answer.";
      case 'joke':
      case 'jokes':
        return "Let's have some laughs! I'll tell you a joke.";
      case 'trivia':
        return "Let's test your knowledge! I'll ask you some trivia questions.";
      case 'spelling':
        return "Let's practice spelling! I'll show you a word and you spell it out loud, letter by letter.";
      case 'math':
      case 'math:random':
        return "Let's practice math! I'll give you some problems to solve.";
      case 'math:addition':
        return "Let's practice addition! I'll give you some problems to solve.";
      case 'math:subtraction':
        return "Let's practice subtraction! I'll give you some problems to solve.";
      case 'math:multiplication':
        return "Let's practice multiplication! I'll give you some problems to solve.";
      case 'math:division':
        return "Let's practice division! I'll give you some problems to solve.";
      case 'truefalse':
      case 'true false':
      case 'true or false':
        return "Let's play true or false! I'll make a statement and you tell me if it's true or false.";
      case 'letters':
      case 'letters:random':
        return "Let's learn letters! I'll show you a letter and you tell me what it is.";
      case 'letters:uppercase':
        return "Let's learn uppercase letters! I'll show you each letter from A to Z.";
      case 'letters:lowercase':
        return "Let's learn lowercase letters! I'll show you each letter from a to z.";
      case 'numbers':
        return "Let's learn numbers! I'll show you a number and you tell me what it is.";
      case 'shapes':
        return "Let's learn shapes! I'll show you a shape and you tell me what it is.";
      case 'animals':
      case 'animals:quiz':
        return "Let's learn about animals! I'll show you an animal and describe it, then you tell me what it's called.";
      case 'animals:lessons':
        return "Let's learn about animals! I'll show you an animal and tell you all about it.";
      case 'animals:random':
        return "Let's explore animals! Sometimes I'll quiz you, and sometimes I'll teach you something new.";
      case 'foods':
      case 'foods:quiz':
        return "Let's learn about foods! I'll show you a food and describe it, then you tell me what it's called.";
      case 'foods:lessons':
        return "Let's learn about foods! I'll show you different foods and tell you all about them.";
      case 'foods:random':
        return "Let's explore foods! Sometimes I'll quiz you, and sometimes I'll teach you something new.";
      case 'geography':
      case 'geography:quiz':
        return "Let's learn about U.S. states! I'll show you a state on the map and give you some clues. Can you guess which state it is?";
      case 'geography:lessons':
        return "Let's learn about U.S. states! I'll show you each state and tell you about it.";
      case 'geography:random':
        return "Let's explore U.S. geography! Sometimes I'll quiz you, and sometimes I'll teach you something new.";
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
    // For spelling mode, spell out each letter clearly for TTS
    if (_state.currentItem?.gradingType == GradingType.spelling) {
      // Generate TTS-safe spelling at runtime with forced pauses
      // Using " ... " creates natural pauses that TTS respects
      final letters = correctAnswer.toUpperCase().split('');
      final spelled = letters.join(' ... ');
      final feedback = "Not quite. The word is ${correctAnswer.toLowerCase()}. $spelled";
      debugPrint('GameController: Spelling feedback TTS: "$feedback"');
      return feedback;
    }
    return "The answer is: $correctAnswer.";
  }

  /// Convert a single letter to its phonetic pronunciation for TTS
  static String _letterToPhonetic(String letter) {
    const phoneticMap = {
      'A': 'Ay', 'B': 'Bee', 'C': 'See', 'D': 'Dee', 'E': 'Eee',
      'F': 'Ef', 'G': 'Jee', 'H': 'Aitch', 'I': 'Eye', 'J': 'Jay',
      'K': 'Kay', 'L': 'El', 'M': 'Em', 'N': 'En', 'O': 'Oh',
      'P': 'Pee', 'Q': 'Cue', 'R': 'Ar', 'S': 'Ess', 'T': 'Tee',
      'U': 'You', 'V': 'Vee', 'W': 'Double-You', 'X': 'Ex', 'Y': 'Why',
      'Z': 'Zee',
    };
    return phoneticMap[letter.toUpperCase()] ?? letter;
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

  /// Pause the game - for quizzes only works during LISTEN phase, for lessons works anytime
  Future<void> pauseGame() async {
    if (!_state.isGameRunning || _isPaused || _isExiting) {
      debugPrint('GameController: Cannot pause - not running or already paused');
      return;
    }

    // For quizzes, only allow pause during LISTEN phase (timer running)
    final isLesson = _state.currentItem?.gradingType == GradingType.none;
    if (!isLesson && _state.phase != LessonPhase.listen) {
      debugPrint('GameController: Cannot pause quiz - not in LISTEN phase');
      return;
    }

    debugPrint('GameController: Pausing game from phase ${_state.phase}');
    _isPaused = true;
    _pausedFromPhase = _state.phase;

    // Stop TTS audio immediately (for lessons)
    if (isLesson) {
      await onStopTTS?.call();
    }

    // Stop mic if active
    if (_isMicActive) {
      _isMicActive = false;
      await onStopMic?.call();
    }

    // Cancel the timer while paused
    _cancelTimer();

    notifyListeners();
  }

  /// Resume the game - restarts timer for quizzes, replays TTS for lessons
  Future<void> resumeGame() async {
    if (!_state.isGameRunning || !_isPaused || _isExiting) {
      debugPrint('GameController: Cannot resume - not paused or not running');
      return;
    }

    debugPrint('GameController: Resuming game to phase $_pausedFromPhase');
    _isPaused = false;

    // For lessons (GradingType.none), replay the current item
    if (_state.currentItem?.gradingType == GradingType.none && _state.currentItem != null) {
      final currentSession = _sessionId;
      _state = _state.copyWith(phase: LessonPhase.ask);
      _pausedFromPhase = null;
      notifyListeners();

      final item = _state.currentItem!;
      if (_state.isAnimalsMode && onPlayAudioFile != null) {
        final audioPath = await AnimalsService.getAudioPath(
          animalId: item.id,
          text: item.ttsPrompt,
          voice: _ttsVoice,
        );
        if (audioPath != null) {
          await onPlayAudioFile!(audioPath);
          return;
        }
      }
      if (_state.isFoodsMode && onPlayAudioFile != null) {
        final audioPath = await FoodsService.getAudioPath(
          foodId: item.id,
          text: item.ttsPrompt,
          voice: _ttsVoice,
        );
        if (audioPath != null) {
          await onPlayAudioFile!(audioPath);
          return;
        }
      }
      await _playTTSAndWait(item.ttsPrompt, currentSession);
      return;
    }

    // For quizzes: restart mic and timer if we were in listen phase
    if (_pausedFromPhase == LessonPhase.listen) {
      _isMicActive = true;
      _startTimer();
      await onStartMic?.call();
    }

    _pausedFromPhase = null;
    notifyListeners();
  }

  /// Skip current question and move to next
  Future<void> skipQuestion() async {
    if (!_state.isActive || _state.phase == LessonPhase.idle || _isExiting) {
      return;
    }

    // Unpause if paused
    _isPaused = false;
    _pausedFromPhase = null;

    final currentSession = _sessionId;

    // Stop mic if listening
    if (_state.phase == LessonPhase.listen) {
      _isMicActive = false;
      await onStopMic?.call();
    }

    // Reveal answer and move on (skip feedback for lessons)
    if (_state.currentItem != null) {
      // For lessons, just move to next item without feedback
      if (_state.currentItem!.gradingType == GradingType.none) {
        _fetchAndAskNextQuestion();
        return;
      }

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

  /// Manually start recording (for when auto-record is off)
  Future<void> startRecording() async {
    if (!_state.isActive || _isExiting) {
      return;
    }

    // Only allow if we're in ASK phase (waiting for user to press Record)
    if (_state.phase != LessonPhase.ask) {
      debugPrint('GameController: Cannot start recording - not in ASK phase (current: ${_state.phase})');
      return;
    }

    debugPrint('GameController: Manual recording start');
    await _transitionToListen();
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
    _cancelTimer();
    _askedItemIds.clear();
    _isExiting = true;
    super.dispose();
  }
}
