import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';
import '../services/shapes_service.dart';
import '../services/animals_service.dart';
import '../services/image_cache_service.dart';
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
  final VoidCallback? onRecord;

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
    this.onRecord,
  });

  @override
  State<GamePageContent> createState() => _GamePageContentState();
}

class _GamePageContentState extends State<GamePageContent> {
  /// Top-level category menus
  bool _showBrainGamesMenu = false;
  bool _showLearningMenu = false;

  /// Sub-category menus (within Learning)
  bool _showMathMenu = false;
  bool _showLettersMenu = false;
  bool _showAnimalsMenu = false;

  /// Track if game was running in previous frame (to detect game end)
  bool _wasGameRunning = false;

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

            // Reset submenus when returning from a game
            final isGameRunning = lessonState.isGameRunning;
            final anyMenuOpen = _showBrainGamesMenu || _showLearningMenu ||
                _showMathMenu || _showLettersMenu || _showAnimalsMenu;
            if (_wasGameRunning && !isGameRunning && anyMenuOpen) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {
                  _showBrainGamesMenu = false;
                  _showLearningMenu = false;
                  _showMathMenu = false;
                  _showLettersMenu = false;
                  _showAnimalsMenu = false;
                });
              });
            }
            _wasGameRunning = isGameRunning;

            return Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      // Green back button (left) - exits game or returns to parent menu
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) async {
                          // If game is running, end the lesson and go to main menu
                          if (lessonState.isGameRunning) {
                            await voiceProvider.endLessonMode();
                            setState(() {
                              _showBrainGamesMenu = false;
                              _showLearningMenu = false;
                              _showMathMenu = false;
                              _showLettersMenu = false;
                              _showAnimalsMenu = false;
                            });
                            return;
                          }

                          if (_showMathMenu || _showLettersMenu) {
                            // Go back to Learning menu
                            setState(() {
                              _showMathMenu = false;
                              _showLettersMenu = false;
                            });
                          } else if (_showAnimalsMenu) {
                            // Animals goes directly to main menu
                            setState(() {
                              _showAnimalsMenu = false;
                              _showLearningMenu = false;
                            });
                          } else if (_showBrainGamesMenu || _showLearningMenu) {
                            // Go back to main games menu
                            setState(() {
                              _showBrainGamesMenu = false;
                              _showLearningMenu = false;
                            });
                          }
                          // On main menu: do nothing (orange button exits to face)
                        },
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
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (_) => widget.onNavigateToFace(),
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
                  onRecord: widget.onRecord,
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
    final gameController = voiceProvider.gameController;

    // Determine status text
    String statusText;
    if (isPaused) {
      statusText = 'Paused';
    } else if (lessonState.phase == LessonPhase.ask && !gameController.autoRecord) {
      // Manual mode: waiting for user to press Answer
      statusText = 'Press answer when ready...';
    } else {
      statusText = lessonState.statusText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        statusText,
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
    final customQuizzes = context.watch<CustomQuizProvider>().quizzes;

    // Show Brain Games submenu
    if (_showBrainGamesMenu) {
      return _buildBrainGamesSubMenu(context, voiceProvider, selectedCategory);
    }

    // Show Learning submenu
    if (_showLearningMenu) {
      // Check for nested submenus within Learning
      if (_showMathMenu) {
        return _buildMathSubMenu(context, voiceProvider, selectedCategory);
      }
      if (_showLettersMenu) {
        return _buildLettersSubMenu(context, voiceProvider, selectedCategory);
      }
      if (_showAnimalsMenu) {
        return _buildAnimalsSubMenu(context, voiceProvider, selectedCategory);
      }
      return _buildLearningSubMenu(context, voiceProvider, selectedCategory);
    }

    // Main menu: Brain Games, Learning, Random, Custom Quizzes
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Fun Games - opens submenu
            _GameOptionButton(
              icon: Icons.psychology,
              title: 'Fun Games',
              subtitle: 'Riddles, jokes, trivia & more',
              isSelected: false,
              onTap: () => setState(() => _showBrainGamesMenu = true),
            ),

            const SizedBox(height: AppSpacing.md),

            // Learning - opens submenu
            _GameOptionButton(
              icon: Icons.school,
              title: 'Learning',
              subtitle: 'Letters, shapes, spelling & more',
              isSelected: false,
              onTap: () => setState(() => _showLearningMenu = true),
            ),

            const SizedBox(height: AppSpacing.md),

            // Random - direct selection
            _GameOptionButton(
              icon: Icons.shuffle,
              title: 'Random',
              subtitle: 'Mix it up',
              isSelected: selectedCategory == 'random',
              onTap: () => voiceProvider.selectLessonCategory('random'),
            ),

            // Custom quizzes
            ...customQuizzes.map((quiz) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: _GameOptionButton(
                icon: Icons.auto_awesome,
                title: quiz.name,
                subtitle: quiz.categoriesDisplay,
                isSelected: selectedCategory == 'custom:${quiz.id}',
                onTap: () => voiceProvider.selectLessonCategory('custom:${quiz.id}'),
              ),
            )),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildBrainGamesSubMenu(BuildContext context, VoiceProvider voiceProvider, String? selectedCategory) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          children: [
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
              icon: Icons.check_circle_outline,
              title: 'True or False',
              subtitle: 'Fact or fiction?',
              isSelected: selectedCategory == 'truefalse',
              onTap: () => voiceProvider.selectLessonCategory('truefalse'),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningSubMenu(BuildContext context, VoiceProvider voiceProvider, String? selectedCategory) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _GameOptionButton(
              icon: Icons.abc,
              title: 'Letters',
              subtitle: 'Learn the alphabet',
              isSelected: selectedCategory?.startsWith('letters') ?? false,
              onTap: () => setState(() => _showLettersMenu = true),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.category,
              title: 'Shapes',
              subtitle: 'Learn shapes',
              isSelected: selectedCategory == 'shapes',
              onTap: () => voiceProvider.selectLessonCategory('shapes'),
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
              icon: Icons.calculate,
              title: 'Math',
              subtitle: 'Practice arithmetic',
              isSelected: selectedCategory?.startsWith('math') ?? false,
              onTap: () => setState(() => _showMathMenu = true),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.pets,
              title: 'Animals',
              subtitle: 'Learn about animals',
              isSelected: selectedCategory?.startsWith('animals') ?? false,
              onTap: () => setState(() => _showAnimalsMenu = true),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildMathSubMenu(BuildContext context, VoiceProvider voiceProvider, String? selectedCategory) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _GameOptionButton(
              icon: Icons.add,
              title: 'Addition',
              subtitle: 'Practice adding numbers',
              isSelected: selectedCategory == 'math:addition',
              onTap: () => voiceProvider.selectLessonCategory('math:addition'),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.remove,
              title: 'Subtraction',
              subtitle: 'Practice subtracting numbers',
              isSelected: selectedCategory == 'math:subtraction',
              onTap: () => voiceProvider.selectLessonCategory('math:subtraction'),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.close,
              title: 'Multiplication',
              subtitle: 'Practice multiplying numbers',
              isSelected: selectedCategory == 'math:multiplication',
              onTap: () => voiceProvider.selectLessonCategory('math:multiplication'),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.safety_divider,
              title: 'Division',
              subtitle: 'Practice dividing numbers',
              isSelected: selectedCategory == 'math:division',
              onTap: () => voiceProvider.selectLessonCategory('math:division'),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.shuffle,
              title: 'Random',
              subtitle: 'Mix all operations',
              isSelected: selectedCategory == 'math:random',
              onTap: () => voiceProvider.selectLessonCategory('math:random'),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildLettersSubMenu(BuildContext context, VoiceProvider voiceProvider, String? selectedCategory) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _GameOptionButton(
              icon: Icons.text_fields,
              title: 'Uppercase A-Z',
              subtitle: 'Learn uppercase letters in order',
              isSelected: selectedCategory == 'letters:uppercase',
              onTap: () => voiceProvider.selectLessonCategory('letters:uppercase'),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.text_format,
              title: 'Lowercase a-z',
              subtitle: 'Learn lowercase letters in order',
              isSelected: selectedCategory == 'letters:lowercase',
              onTap: () => voiceProvider.selectLessonCategory('letters:lowercase'),
            ),

            const SizedBox(height: AppSpacing.md),

            _GameOptionButton(
              icon: Icons.shuffle,
              title: 'Random',
              subtitle: 'Mix of uppercase and lowercase',
              isSelected: selectedCategory == 'letters:random',
              onTap: () => voiceProvider.selectLessonCategory('letters:random'),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimalsSubMenu(BuildContext context, VoiceProvider voiceProvider, String? selectedCategory) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _AnimalOptionCard(
              icon: Icons.school,
              title: 'Lessons',
              subtitle: 'Learn about animals',
              description: 'See pictures and hear fun facts about mammals, birds, fish, reptiles, and more',
              isSelected: selectedCategory == 'animals:lessons',
              onTap: () => voiceProvider.selectLessonCategory('animals:lessons'),
            ),

            const SizedBox(height: AppSpacing.lg),

            _AnimalOptionCard(
              icon: Icons.quiz,
              title: 'Quiz',
              subtitle: 'Test your knowledge',
              description: 'See an animal and try to name it - how many can you get right?',
              isSelected: selectedCategory == 'animals:quiz',
              onTap: () => voiceProvider.selectLessonCategory('animals:quiz'),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
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
    // For letters: show just the letter in large font
    // For shapes: show the shape icon with hint
    // For animals: show the animal image with description
    // For others: show the full question
    if (lessonState.isSpellingMode) {
      return _buildSpellingDisplay(context, lessonState, remainingSeconds);
    } else if (lessonState.isLettersMode) {
      return _buildLettersDisplay(context, lessonState, remainingSeconds);
    } else if (lessonState.isShapesMode) {
      return _buildShapesDisplay(context, lessonState, remainingSeconds);
    } else if (lessonState.category == 'animals:lessons') {
      return _buildAnimalsLessonDisplay(context, lessonState);
    } else if (lessonState.isAnimalsMode) {
      return _buildAnimalsQuizDisplay(context, lessonState, remainingSeconds);
    } else {
      return _buildDefaultDisplay(context, lessonState, remainingSeconds);
    }
  }

  /// Get intro title and subtitle for a category
  (String title, String subtitle) _getIntroText(String category) {
    // Handle custom quiz
    if (category.startsWith('custom:')) {
      final quizId = category.substring(7);
      final quiz = context.read<CustomQuizProvider>().getQuizById(quizId);
      if (quiz != null) {
        return ("Let's play ${quiz.name}!", "I'll mix in some ${quiz.categoriesDisplay.toLowerCase()}.");
      }
      return ("Let's play!", "I'll ask you some questions.");
    }

    switch (category.toLowerCase()) {
      case 'riddle':
      case 'riddles':
        return ("Let's do some riddles!", "I'll ask you a riddle and you try to guess the answer.");
      case 'joke':
      case 'jokes':
        return ("Let's have some laughs!", "I'll tell you a joke.");
      case 'trivia':
        return ("Let's test your knowledge!", "I'll ask you some trivia questions.");
      case 'truefalse':
      case 'true false':
      case 'true or false':
        return ("True or False!", "I'll make a statement and you tell me if it's true or false.");
      case 'spelling':
        return ("Let's practice spelling!", "I'll show you a word and you spell it out loud, letter by letter.");
      case 'letters':
      case 'letters:random':
        return ("Let's learn letters!", "I'll show you a letter and you tell me what it is.");
      case 'letters:uppercase':
        return ("Uppercase Letters!", "I'll show you each letter from A to Z.");
      case 'letters:lowercase':
        return ("Lowercase Letters!", "I'll show you each letter from a to z.");
      case 'math':
      case 'math:random':
        return ("Let's practice math!", "I'll give you some problems to solve.");
      case 'math:addition':
        return ("Let's practice addition!", "I'll give you some problems to solve.");
      case 'math:subtraction':
        return ("Let's practice subtraction!", "I'll give you some problems to solve.");
      case 'math:multiplication':
        return ("Let's practice multiplication!", "I'll give you some problems to solve.");
      case 'math:division':
        return ("Let's practice division!", "I'll give you some problems to solve.");
      case 'shapes':
        return ("Let's learn shapes!", "I'll show you a shape and give you a hint.");
      case 'animals':
      case 'animals:quiz':
        return ("Let's learn about animals!", "I'll show you an animal and describe it.");
      case 'animals:lessons':
        return ("Let's learn about animals!", "I'll show you animals and tell you fun facts.");
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

    // Get display size setting (large = 50% bigger than normal)
    final isLarge = context.watch<GameSettingsProvider>().isLargeDisplay;
    final wordFontSize = isLarge ? 144.0 : 96.0;
    final progressFontSize = isLarge ? 33.0 : 22.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isLarge ? AppSpacing.xl : AppSpacing.lg,
        horizontal: isLarge ? AppSpacing.xl : AppSpacing.lg,
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
                  fontSize: progressFontSize,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),

          const Spacer(flex: 1),

          // LARGE WORD DISPLAY - clean style like Riddles
          Text(
            word.isEmpty ? '...' : word.toLowerCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: wordFontSize,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              letterSpacing: isLarge ? 5 : 3,
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

  Widget _buildLettersDisplay(BuildContext context, LessonState lessonState, int? remainingSeconds) {
    final letter = lessonState.displayQuestion;

    // Get display size setting (letter size is fixed, prompt adjusts)
    final isLarge = context.watch<GameSettingsProvider>().isLargeDisplay;
    const letterFontSize = 180.0; // Fixed size
    final promptFontSize = isLarge ? 48.0 : 32.0;
    final progressFontSize = isLarge ? 33.0 : 22.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isLarge ? AppSpacing.xl : AppSpacing.lg,
        horizontal: isLarge ? AppSpacing.xl : AppSpacing.lg,
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
                  fontSize: progressFontSize,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),

          const Spacer(flex: 1),

          // Prompt text
          Text(
            'What letter is this?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: promptFontSize,
              color: Colors.white.withOpacity(0.7),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // LARGE LETTER DISPLAY
          Text(
            letter.isEmpty ? '...' : letter,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: letterFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
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

  Widget _buildShapesDisplay(BuildContext context, LessonState lessonState, int? remainingSeconds) {
    final hint = lessonState.displayQuestion; // "This shape has 3 sides. What is it?"
    final shapeId = lessonState.currentItem?.id ?? '';
    final assetPath = ShapesService.getAssetPath(shapeId) ?? 'assets/shapes/circle.png';

    // Shape size is fixed, but hint text respects display size setting (large = 50% bigger)
    const shapeSize = 260.0;
    final isLarge = context.watch<GameSettingsProvider>().isLargeDisplay;
    final hintFontSize = isLarge ? 48.0 : 32.0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.xl,
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
                  fontSize: isLarge ? 33.0 : 22.0,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),

          const Spacer(flex: 1),

          // SHAPE IMAGE
          Image.asset(
            assetPath,
            width: shapeSize,
            height: shapeSize,
            fit: BoxFit.contain,
          ),

          const SizedBox(height: AppSpacing.xl),

          // Hint text: "This shape has 3 sides. What is it?"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: hintFontSize,
                color: Colors.white.withOpacity(0.9),
                height: 1.3,
              ),
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

  /// Build animal image widget - uses cached local file if available, otherwise network
  Widget _buildAnimalImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        height: 200,
        color: Colors.white.withOpacity(0.1),
        child: Center(
          child: Icon(
            Icons.pets,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
        ),
      );
    }

    // Check for cached local file
    final localPath = ImageCacheService.getLocalPath(imageUrl);
    if (localPath != null) {
      return Image.file(
        File(localPath),
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (context, error, stackTrace) {
          // Fall back to network if local file fails
          return Image.network(
            imageUrl,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 200,
                color: Colors.white.withOpacity(0.1),
                child: Center(
                  child: Icon(
                    Icons.pets,
                    size: 80,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // No cache - use network
    return Image.network(
      imageUrl,
      width: double.infinity,
      fit: BoxFit.fitWidth,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 200,
          color: Colors.white.withOpacity(0.1),
          child: Center(
            child: Icon(
              Icons.pets,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        );
      },
    );
  }

  /// Animals Lesson display - image at top, name, then description
  Widget _buildAnimalsLessonDisplay(BuildContext context, LessonState lessonState) {
    final description = lessonState.displayQuestion;
    final animalName = lessonState.displayAnswer;
    final imageUrl = lessonState.currentItem?.imageUrl;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image - 80% width at top, centered
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildAnimalImage(imageUrl),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Name under image
          Text(
            animalName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Description under name
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 20,
              color: Colors.white.withOpacity(0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Animals Quiz display - matches lesson style for image
  Widget _buildAnimalsQuizDisplay(BuildContext context, LessonState lessonState, int? remainingSeconds) {
    final imageUrl = lessonState.currentItem?.imageUrl;

    final isLarge = context.watch<GameSettingsProvider>().isLargeDisplay;
    final promptFontSize = isLarge ? 36.0 : 28.0;
    final progressFontSize = isLarge ? 22.0 : 16.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress indicator
          if (lessonState.questionCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                lessonState.progressText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: progressFontSize,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),

          // Image - 80% width, centered (matches lesson style)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildAnimalImage(imageUrl),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Simple prompt - just ask "What animal is this?"
          Text(
            'What animal is this?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: promptFontSize,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Timer during LISTEN phase, Answer during FEEDBACK phase
          _buildTimerOrAnswer(context, lessonState),
        ],
      ),
    );
  }

  Widget _buildDefaultDisplay(BuildContext context, LessonState lessonState, int? remainingSeconds) {
    final questionText = lessonState.displayQuestion;
    final isMath = lessonState.currentItem?.type == 'math';

    // Get display size setting (large = 50% bigger than normal)
    final isLarge = context.watch<GameSettingsProvider>().isLargeDisplay;
    final mathFontSize = isLarge ? 126.0 : 84.0;
    final questionFontSize = isLarge ? 63.0 : 42.0;
    final progressFontSize = isLarge ? 33.0 : 22.0;

    // Check if this is a multi-digit math problem that should be stacked
    final shouldStack = isMath && _shouldStackMathProblem(questionText);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isLarge ? AppSpacing.xl : AppSpacing.lg,
        horizontal: isLarge ? AppSpacing.xl : AppSpacing.lg,
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
                  fontSize: progressFontSize,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),

          const Spacer(flex: 1),

          // Main question - stacked for multi-digit math, horizontal otherwise
          if (shouldStack)
            _buildStackedMathDisplay(questionText, isLarge: isLarge)
          else
            Text(
              questionText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: isMath ? mathFontSize : questionFontSize,
                fontWeight: isMath ? FontWeight.w600 : FontWeight.w400,
                color: Colors.white,
                height: 1.3,
                letterSpacing: isMath ? 2 : 0,
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

  /// Check if a math problem should be displayed in stacked format
  /// Stack if either operand has 2+ digits (medium/hard problems)
  bool _shouldStackMathProblem(String question) {
    final parts = _parseMathProblem(question);
    if (parts == null) return false;

    final (num1, _, num2) = parts;
    // Stack if either number has 2+ digits
    return num1.length >= 2 || num2.length >= 2;
  }

  /// Parse a math problem string like "88 × 12" into (num1, operator, num2)
  /// Returns null if parsing fails
  (String, String, String)? _parseMathProblem(String question) {
    // Match patterns like "88 × 12", "5 + 3", "45 - 8", "24 ÷ 6"
    final regex = RegExp(r'^(\d+)\s*([+\-×÷])\s*(\d+)$');
    final match = regex.firstMatch(question.trim());

    if (match == null) return null;

    return (match.group(1)!, match.group(2)!, match.group(3)!);
  }

  /// Build a stacked vertical math display for multi-digit problems
  /// Shows the problem in traditional vertical format:
  ///     23
  ///   ×  4
  ///   ────
  Widget _buildStackedMathDisplay(String question, {bool isLarge = false}) {
    final parts = _parseMathProblem(question);
    final fallbackFontSize = isLarge ? 126.0 : 84.0;

    if (parts == null) {
      // Fallback to horizontal display
      return Text(
        question,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: fallbackFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 2,
        ),
      );
    }

    final (num1, operator, num2) = parts;

    // Sizes based on display setting (large = 50% bigger than normal)
    final numberFontSize = isLarge ? 114.0 : 76.0;
    final operatorFontSize = isLarge ? 96.0 : 64.0;
    final digitWidth = isLarge ? 72.0 : 48.0;

    // Calculate the width needed based on the longer number
    final maxDigits = num1.length > num2.length ? num1.length : num2.length;
    final lineWidth = (maxDigits + 2) * digitWidth;

    final numberStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: numberFontSize,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      letterSpacing: 4,
      height: 1.2,
    );

    final operatorStyle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: operatorFontSize,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // First number (right-aligned)
        Text(num1, style: numberStyle),

        const SizedBox(height: 4),

        // Operator + second number row
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(operator, style: operatorStyle),
            SizedBox(width: isLarge ? 16 : 12),
            Text(num2, style: numberStyle),
          ],
        ),

        SizedBox(height: isLarge ? 12 : 8),

        // Horizontal line
        Container(
          width: lineWidth,
          height: isLarge ? 6 : 4,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
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
    final isCorrect = lessonState.isCorrect == true;

    // For letters mode, just show "Correct!" or "Incorrect" without the answer
    if (lessonState.isLettersMode) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: AppSpacing.md),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg,
          horizontal: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: isCorrect
              ? Colors.green.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
          border: Border.all(
            color: isCorrect
                ? Colors.green.withOpacity(0.5)
                : Colors.orange.withOpacity(0.5),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(AppBorderRadius.large),
        ),
        child: Text(
          isCorrect ? 'Correct!' : 'Incorrect',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: isCorrect ? Colors.green : Colors.orange,
          ),
        ),
      );
    }

    // For spelling mode, space out the letters: "apple" -> "a  p  p  l  e"
    final displayText = lessonState.isSpellingMode
        ? answerText.toLowerCase().split('').join('  ')
        : answerText;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: isCorrect
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        border: Border.all(
          color: isCorrect
              ? Colors.green.withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
      ),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: lessonState.isSpellingMode ? 36 : 28,
          fontWeight: FontWeight.w600,
          letterSpacing: lessonState.isSpellingMode ? 4 : 0,
          color: isCorrect ? Colors.green : Colors.orange,
        ),
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

/// Taller card for Animals submenu with description
class _AnimalOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final VoidCallback onTap;
  final bool isSelected;

  const _AnimalOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.dreamCloudBlue.withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? AppColors.dreamCloudBlue : Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppColors.dreamCloudBlue : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 18,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              description,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                color: Colors.white.withOpacity(0.5),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
