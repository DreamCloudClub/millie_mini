import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';
import 'lesson_phase.dart';

/// Game display page for riddles, jokes, and interactive games
/// Uses the FSM-based GameController for lesson mode
class GamePageContent extends StatelessWidget {
  final VoidCallback onNavigateToFace;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final Future<void> Function() onRefresh;
  final VoidCallback onExit;

  const GamePageContent({
    super.key,
    required this.onNavigateToFace,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
  });

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
                      // Green refresh button (left) - resets game to menu
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
                            Icons.refresh,
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
                        onTap: onNavigateToFace,
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
                        child: lessonState.isActive
                            ? _buildLessonDisplay(context, lessonState)
                            : _buildMenuState(context, voiceProvider),
                      ),
                    ),
                  ),
                ),

                // Status text - uses FSM phase status
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Mic indicator - shows when LISTEN phase AND mic is actually active
                      // Uses controller's isMicActive which combines phase check with real mic state
                      if (voiceProvider.gameController.isMicActive) ...[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        lessonState.isActive
                            ? lessonState.statusText
                            : voiceProvider.state.statusText,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom control bar
                ControlBar(
                  onPause: onPause,
                  onPlay: onPlay,
                  onRefresh: onRefresh,
                  onExit: onExit,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuState(BuildContext context, VoiceProvider voiceProvider) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          const Spacer(),

          // Game options - now using startLessonCategory
          _GameOptionButton(
            icon: Icons.psychology,
            title: 'Riddles',
            subtitle: 'Test your thinking',
            onTap: () => voiceProvider.startLessonCategory('riddle'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.sentiment_very_satisfied,
            title: 'Jokes',
            subtitle: 'Laugh along',
            onTap: () => voiceProvider.startLessonCategory('joke'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.quiz_outlined,
            title: 'Trivia',
            subtitle: 'Test your knowledge',
            onTap: () => voiceProvider.startLessonCategory('trivia'),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.shuffle,
            title: 'Random',
            subtitle: 'Mix it up',
            onTap: () => voiceProvider.startLessonCategory('random'),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLessonDisplay(BuildContext context, LessonState lessonState) {
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
            questionText.isEmpty ? 'Starting...' : questionText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.w400,
              color: questionText.isEmpty
                  ? Colors.white.withOpacity(0.5)
                  : Colors.white,
              height: 1.3,
            ),
          ),

          const Spacer(flex: 1),

          // Answer section (when revealed in FEEDBACK phase)
          if (showAnswer && answerText.isNotEmpty)
            Container(
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
            ),

          const Spacer(flex: 1),
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

  const _GameOptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
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
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
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
