import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';
import 'lesson_phase.dart';

/// Game display page for riddles, jokes, and interactive games
/// Uses the FSM-based GameController for lesson mode
class GamePageContent extends StatefulWidget {
  final VoidCallback onNavigateToFace;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final Future<void> Function() onRefresh;
  final VoidCallback onExit;
  final VoidCallback? onSkip;
  final VoidCallback? onStart;
  final VoidCallback? onGamePause;
  final VoidCallback? onGameResume;

  const GamePageContent({
    super.key,
    required this.onNavigateToFace,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
    this.onSkip,
    this.onStart,
    this.onGamePause,
    this.onGameResume,
  });

  @override
  State<GamePageContent> createState() => _GamePageContentState();
}

class _GamePageContentState extends State<GamePageContent> {
  @override
  void initState() {
    super.initState();
    _ensureStatusBarVisible();
  }

  /// Ensure status bar is always visible on game page
  void _ensureStatusBarVisible() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: SafeArea(
        child: Consumer<VoiceProvider>(
          builder: (context, voiceProvider, _) {
            final lessonState = voiceProvider.lessonState;

            return Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      // Green back button (left) - returns to games menu
                      GestureDetector(
                        onTap: () => voiceProvider.endLessonMode(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),

                      // Title (centered)
                      const Expanded(
                        child: Text(
                          'AI Games',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      // Orange back button (right)
                      GestureDetector(
                        onTap: widget.onNavigateToFace,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content area in bordered container
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: lessonState.isGameRunning
                            ? _buildLessonDisplay(context, lessonState)
                            : _buildMenuState(context, voiceProvider, lessonState),
                      ),
                    ),
                  ),
                ),

                // Circular timer and status area
                _buildTimerArea(context, voiceProvider, lessonState),

                // Bottom control bar
                ControlBar(
                  onPause: widget.onPause,
                  onPlay: widget.onPlay,
                  onRefresh: widget.onRefresh,
                  onExit: widget.onExit,
                  onSkip: widget.onSkip,
                  onStart: widget.onStart,
                  onGamePause: widget.onGamePause,
                  onGameResume: widget.onGameResume,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimerArea(BuildContext context, VoiceProvider voiceProvider, LessonState lessonState) {
    final isPaused = voiceProvider.isGamePaused;

    // Just show status text - timer is now inside the content area
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        isPaused
            ? 'Paused'
            : lessonState.isActive
                ? lessonState.statusText
                : voiceProvider.state.statusText,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 14,
          color: Colors.white.withOpacity(0.5),
        ),
      ),
    );
  }

  /// Circular timer widget for the answer area
  Widget _buildCircularTimer(int remainingSeconds, int totalSeconds) {
    final progress = remainingSeconds / totalSeconds;
    final isLow = remainingSeconds < 5;

    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withOpacity(0.2),
              ),
            ),
          ),
          // Progress circle
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                isLow ? Colors.red : AppColors.dreamCloudBlue,
              ),
            ),
          ),
          // Time text in center
          Text(
            '$remainingSeconds',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isLow ? Colors.red : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuState(BuildContext context, VoiceProvider voiceProvider, LessonState lessonState) {
    final selectedCategory = lessonState.isSelected ? lessonState.category : null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          const Spacer(),

          // Game options - select category, then press Start
          _GameOptionButton(
            icon: Icons.psychology,
            title: 'Riddles',
            subtitle: 'Test your thinking',
            isSelected: selectedCategory == 'riddle',
            onTap: () => voiceProvider.selectLessonCategory('riddle'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.sentiment_very_satisfied,
            title: 'Jokes',
            subtitle: 'Laugh along',
            isSelected: selectedCategory == 'joke',
            onTap: () => voiceProvider.selectLessonCategory('joke'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.quiz_outlined,
            title: 'Trivia',
            subtitle: 'Test your knowledge',
            isSelected: selectedCategory == 'trivia',
            onTap: () => voiceProvider.selectLessonCategory('trivia'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.spellcheck,
            title: 'Spelling',
            subtitle: 'Spell words out loud',
            isSelected: selectedCategory == 'spelling',
            onTap: () => voiceProvider.selectLessonCategory('spelling'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.shuffle,
            title: 'Random',
            subtitle: 'Mix it up',
            isSelected: selectedCategory == 'random',
            onTap: () => voiceProvider.selectLessonCategory('random'),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLessonDisplay(BuildContext context, LessonState lessonState) {
    final voiceProvider = context.read<VoiceProvider>();
    final remainingSeconds = voiceProvider.gameController.remainingSeconds;

    // Show intro view during intro phase
    if (lessonState.phase == LessonPhase.intro) {
      return _buildIntroDisplay(lessonState.category);
    }

    // For spelling: show just the word (from item.displayText)
    // For others: show the full question
    if (lessonState.isSpellingMode) {
      return _buildSpellingDisplay(context, lessonState, remainingSeconds);
    } else {
      return _buildDefaultDisplay(context, lessonState, remainingSeconds);
    }
  }

  /// Get intro title and subtitle for a category
  (String title, String subtitle) _getIntroText(String category) {
    switch (category.toLowerCase()) {
      case 'riddle':
      case 'riddles':
        return ("Let's do some riddles!", "I'll ask you a riddle and you try to guess the answer.");
      case 'joke':
      case 'jokes':
        return ("Let's have some laughs!", "I'll tell you a joke.");
      case 'trivia':
        return ("Let's test your knowledge!", "I'll ask you some trivia questions.");
      case 'spelling':
        return ("Let's practice spelling!", "I'll show you a word and you spell it out loud, letter by letter.");
      default:
        return ("Let's play!", "I'll ask you some questions.");
    }
  }

  Widget _buildIntroDisplay(String category) {
    final (title, subtitle) = _getIntroText(category);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Millie face icon with white border
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Image.asset(
                'assets/icon/icon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.games,
                    size: 60,
                    color: Colors.white,
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpellingDisplay(BuildContext context, LessonState lessonState, int? remainingSeconds) {
    final word = lessonState.displayQuestion;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          // Progress indicator
          if (lessonState.questionCount > 0)
            Text(
              lessonState.progressText,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),

          const Spacer(),

          // LARGE WORD DISPLAY
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withOpacity(0.3), width: 2),
            ),
            child: Text(
              word.isEmpty ? '...' : word.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
          ),

          const Spacer(),

          // Timer during LISTEN phase, Answer during FEEDBACK phase
          _buildTimerOrAnswer(context, lessonState),
        ],
      ),
    );
  }

  Widget _buildDefaultDisplay(BuildContext context, LessonState lessonState, int? remainingSeconds) {
    final showAnswer = lessonState.isCorrect != null;
    final questionText = lessonState.displayQuestion;
    final answerText = lessonState.displayAnswer;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        children: [
          // Progress indicator
          if (lessonState.questionCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                lessonState.progressText,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),

          const Spacer(flex: 1),

          // Main question in large text
          Text(
            questionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.w400,
              color: Colors.white,
              height: 1.3,
            ),
          ),

          const Spacer(flex: 1),

          // Timer during LISTEN phase, Answer during FEEDBACK phase
          _buildTimerOrAnswer(context, lessonState),

          const Spacer(flex: 1),
        ],
      ),
    );
  }

  /// Shows timer during LISTEN, answer during FEEDBACK, empty otherwise
  Widget _buildTimerOrAnswer(BuildContext context, LessonState lessonState) {
    final voiceProvider = context.read<VoiceProvider>();
    final remainingSeconds = voiceProvider.gameController.remainingSeconds;
    final totalSeconds = voiceProvider.gameController.timeLimitSeconds;
    final isPaused = voiceProvider.isGamePaused;

    // During LISTEN phase with timer active (not paused) - show circular timer
    if (lessonState.phase == LessonPhase.listen &&
        !isPaused &&
        remainingSeconds != null &&
        totalSeconds != null &&
        totalSeconds > 0) {
      return _buildCircularTimer(remainingSeconds, totalSeconds);
    }

    // During FEEDBACK phase - show answer
    if (lessonState.isCorrect != null && lessonState.displayAnswer.isNotEmpty) {
      return _buildAnswerFeedback(lessonState);
    }

    // Otherwise return empty sized box to maintain layout
    return const SizedBox(height: 100);
  }

  Widget _buildAnswerFeedback(LessonState lessonState) {
    final answerText = lessonState.displayAnswer;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border.all(
          color: lessonState.isCorrect == true
              ? Colors.green.withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.medium),
      ),
      child: Column(
        children: [
          // Correct/incorrect indicator
          Icon(
            lessonState.isCorrect == true
                ? Icons.check_circle
                : Icons.info_outline,
            color: lessonState.isCorrect == true
                ? Colors.green
                : Colors.orange,
            size: 32,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            answerText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: lessonState.isCorrect == true
                  ? Colors.green
                  : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

/// Game option button widget
class _GameOptionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isSelected;

  const _GameOptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppBorderRadius.large),
          border: Border.all(
            color: isSelected
                ? AppColors.dreamCloudBlue
                : Colors.white.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.dreamCloudBlue.withOpacity(0.2)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.dreamCloudBlue : Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.dreamCloudBlue : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
