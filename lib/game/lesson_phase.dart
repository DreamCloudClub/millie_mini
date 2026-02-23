import 'lesson_item.dart';

/// Lesson mode phases for the deterministic FSM
enum LessonPhase {
  /// Not in lesson mode
  idle,

  /// Category selected, waiting for user to press Start
  selected,

  /// Playing intro message ("Let's do some riddles!")
  intro,

  /// Asking the question (TTS playing prompt)
  ask,

  /// Listening for user's answer (mic active)
  listen,

  /// Evaluating the answer (deterministic check)
  eval,

  /// Playing feedback ("Correct!" or "The answer is X")
  feedback,

  /// Exiting lesson mode ("Thanks for playing!")
  exiting,
}

extension LessonPhaseExtension on LessonPhase {
  /// Human-readable status text for UI display
  String get statusText {
    switch (this) {
      case LessonPhase.idle:
        return 'Select Topic';
      case LessonPhase.selected:
        return 'Press Start';
      case LessonPhase.intro:
        return 'Starting...';
      case LessonPhase.ask:
        return 'Talking...';
      case LessonPhase.listen:
        return 'Listening...';
      case LessonPhase.eval:
        return 'Checking...';
      case LessonPhase.feedback:
        return 'Speaking...';
      case LessonPhase.exiting:
        return 'Ending...';
    }
  }

  /// Whether mic should be active in this phase
  bool get isMicActive => this == LessonPhase.listen;

  /// Whether TTS is playing in this phase
  bool get isSpeaking =>
      this == LessonPhase.intro ||
      this == LessonPhase.ask ||
      this == LessonPhase.feedback ||
      this == LessonPhase.exiting;
}

/// Immutable state for lesson mode FSM
class LessonState {
  final LessonPhase phase;
  final String category;
  final LessonItem? currentItem;
  final String? userAnswer;
  final bool? isCorrect;
  final int questionCount;
  final int correctCount;

  const LessonState({
    this.phase = LessonPhase.idle,
    this.category = '',
    this.currentItem,
    this.userAnswer,
    this.isCorrect,
    this.questionCount = 0,
    this.correctCount = 0,
  });

  /// Factory for idle state
  static const LessonState idle = LessonState();

  /// Whether lesson mode is active (not idle)
  bool get isActive => phase != LessonPhase.idle;

  /// Whether the game is actually running (past the selected phase)
  bool get isGameRunning =>
      phase != LessonPhase.idle && phase != LessonPhase.selected;

  /// Whether a category has been selected (ready to start)
  bool get isSelected => phase == LessonPhase.selected;

  /// Status text for UI (from phase)
  String get statusText => phase.statusText;

  /// Whether mic should be active
  bool get isMicActive => phase.isMicActive;

  /// Current question text for display
  String get displayQuestion => currentItem?.prompt ?? '';

  /// Current answer text for display (when revealed)
  String get displayAnswer => currentItem?.answer ?? '';

  /// Get the current item's grading type
  GradingType? get gradingType => currentItem?.gradingType;

  /// Whether current question is spelling mode
  bool get isSpellingMode => currentItem?.gradingType == GradingType.spelling;

  /// Whether current question is letters mode
  bool get isLettersMode => currentItem?.type == 'letters';

  /// Whether current question is numbers mode
  bool get isNumbersMode => currentItem?.type == 'numbers';

  /// Whether current question is shapes mode
  bool get isShapesMode => currentItem?.type == 'shapes';

  /// Whether current question is animals mode (quiz or lesson)
  bool get isAnimalsMode => currentItem?.type == 'animals' || currentItem?.type == 'animals:lesson' || category.startsWith('animals');

  /// Whether current question is foods mode (quiz or lesson)
  bool get isFoodsMode => currentItem?.type == 'foods' || currentItem?.type == 'foods:lesson' || category.startsWith('foods');

  /// Whether current question is geography mode (quiz or lesson)
  bool get isGeographyMode => currentItem?.type == 'geography' || currentItem?.type == 'geography:lesson' || category.startsWith('geography');

  /// Display text showing progress
  String get progressText {
    if (!isActive) return '';
    return 'Question $questionCount • $correctCount correct';
  }

  /// Create a copy with updated fields
  LessonState copyWith({
    LessonPhase? phase,
    String? category,
    LessonItem? currentItem,
    String? userAnswer,
    bool? isCorrect,
    int? questionCount,
    int? correctCount,
    bool clearCurrentItem = false,
    bool clearUserAnswer = false,
    bool clearIsCorrect = false,
  }) {
    return LessonState(
      phase: phase ?? this.phase,
      category: category ?? this.category,
      currentItem: clearCurrentItem ? null : (currentItem ?? this.currentItem),
      userAnswer: clearUserAnswer ? null : (userAnswer ?? this.userAnswer),
      isCorrect: clearIsCorrect ? null : (isCorrect ?? this.isCorrect),
      questionCount: questionCount ?? this.questionCount,
      correctCount: correctCount ?? this.correctCount,
    );
  }

  @override
  String toString() {
    return 'LessonState(phase: $phase, category: $category, '
        'question: $questionCount, correct: $correctCount)';
  }
}
