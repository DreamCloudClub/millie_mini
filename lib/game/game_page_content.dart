import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';

/// Game display page for riddles, jokes, and interactive games
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
            final gameState = voiceProvider.gameState;
            debugPrint('GamePageContent rebuild: isActive=${gameState.isActive}, question=${gameState.question}');

            return Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      // Green refresh button (left) - resets game to menu
                      GestureDetector(
                        onTap: () => voiceProvider.endGame(),
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
                        child: gameState.isActive
                            ? _buildGameDisplay(context, gameState)
                            : _buildMenuState(context, voiceProvider),
                      ),
                    ),
                  ),
                ),

                // Status text
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    voiceProvider.state.statusText,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
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

          // Game options
          _GameOptionButton(
            icon: Icons.psychology,
            title: 'Riddles',
            subtitle: 'Test your thinking',
            onTap: () => voiceProvider.startGameCategory(GameType.riddle),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.sentiment_very_satisfied,
            title: 'Jokes',
            subtitle: 'Laugh along',
            onTap: () => voiceProvider.startGameCategory(GameType.joke),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.quiz_outlined,
            title: 'Trivia',
            subtitle: 'Test your knowledge',
            onTap: () => voiceProvider.startGameCategory(GameType.trivia),
          ),

          const SizedBox(height: AppSpacing.md),

          _GameOptionButton(
            icon: Icons.shuffle,
            title: 'Random',
            subtitle: 'Mix it up',
            onTap: () => voiceProvider.startGameCategory(GameType.random),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildGameDisplay(BuildContext context, GameState gameState) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        children: [
          const Spacer(flex: 1),

          // Main question in large text
          Text(
            gameState.question.isEmpty ? 'Waiting for content...' : gameState.question,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.w400,
              color: gameState.question.isEmpty ? Colors.white.withOpacity(0.5) : Colors.white,
              height: 1.3,
            ),
          ),

          const Spacer(flex: 1),

          // Answer section (when revealed)
          if (gameState.answer != null && gameState.isAnswerRevealed)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
              ),
              child: Text(
                gameState.answer!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.green,
                ),
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

/// Game types
enum GameType {
  riddle,
  joke,
  trivia,
  random,
}

/// Current game state
class GameState {
  final bool isActive;
  final GameType type;
  final String? questionId; // DB question ID
  final String question;
  final String? answer;
  final bool isAnswerRevealed;
  final int questionCount; // How many questions asked in this session

  const GameState({
    this.isActive = false,
    this.type = GameType.riddle,
    this.questionId,
    this.question = '',
    this.answer,
    this.isAnswerRevealed = false,
    this.questionCount = 0,
  });

  GameState copyWith({
    bool? isActive,
    GameType? type,
    String? questionId,
    String? question,
    String? answer,
    bool? isAnswerRevealed,
    int? questionCount,
  }) {
    return GameState(
      isActive: isActive ?? this.isActive,
      type: type ?? this.type,
      questionId: questionId ?? this.questionId,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      isAnswerRevealed: isAnswerRevealed ?? this.isAnswerRevealed,
      questionCount: questionCount ?? this.questionCount,
    );
  }

  GameState revealAnswer(String answerText) {
    return copyWith(
      answer: answerText,
      isAnswerRevealed: true,
    );
  }

  static const GameState inactive = GameState();
}
