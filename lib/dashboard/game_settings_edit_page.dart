import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_settings_provider.dart';
import '../providers/custom_quiz_provider.dart';
import '../models/game_settings.dart';
import '../models/custom_quiz.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class GameSettingsEditPage extends StatefulWidget {
  final VoidCallback onSaved;
  final void Function(String? quizId) onEditCustomQuiz;

  const GameSettingsEditPage({
    super.key,
    required this.onSaved,
    required this.onEditCustomQuiz,
  });

  @override
  State<GameSettingsEditPage> createState() => _GameSettingsEditPageState();
}

class _GameSettingsEditPageState extends State<GameSettingsEditPage> {
  TimeLimit _timeLimit = TimeLimit.none;
  GameDifficulty _difficulty = GameDifficulty.medium;
  bool _autoRecord = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  void _loadSettings() {
    final settings = context.read<GameSettingsProvider>().settings;
    setState(() {
      _timeLimit = settings.timeLimit;
      _difficulty = settings.difficulty;
      _autoRecord = settings.autoRecord;
    });
  }

  Future<void> _handleSave() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<GameSettingsProvider>();
      await provider.updateSettings(GameSettings(
        timeLimit: _timeLimit,
        difficulty: _difficulty,
        autoRecord: _autoRecord,
      ));

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      widget.onSaved();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Game Settings',
            style: AppTextStyles.heading2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onSaved,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // General Settings Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDropdown<TimeLimit>(
                    label: 'Time Limit',
                    value: _timeLimit,
                    items: TimeLimit.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.displayName),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _timeLimit = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Countdown timer during the listening phase. When it expires, the question is skipped.',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppDropdown<GameDifficulty>(
                    label: 'Difficulty',
                    value: _difficulty,
                    items: GameDifficulty.values
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d.displayName),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _difficulty = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Filters questions by age-appropriate difficulty level.',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Auto-Record',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Switch(
                        value: _autoRecord,
                        onChanged: (value) {
                          setState(() {
                            _autoRecord = value;
                          });
                        },
                        activeColor: AppColors.dreamCloudBlue,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _autoRecord
                        ? 'Mic starts automatically after each question. Timer counts down.'
                        : 'Press Record button to answer each question. No time pressure.',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Custom Quizzes Section
            _buildCustomQuizzesSection(),

            // Generous space after Custom Quizzes
            const SizedBox(height: 48),

            // Save button
            AppButton(
              label: 'Save Settings',
              onPressed: _isLoading ? null : _handleSave,
              isLoading: _isLoading,
              isFullWidth: true,
              customColor: AppColors.dreamCloudBlue,
            ),

            // Bottom safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomQuizzesSection() {
    return Consumer<CustomQuizProvider>(
      builder: (context, quizProvider, _) {
        final quizzes = quizProvider.quizzes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section header with Add button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Custom Quizzes',
                  style: AppTextStyles.heading3,
                ),
                OutlinedButton.icon(
                  onPressed: () => widget.onEditCustomQuiz(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add New'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dreamCloudBlue,
                    side: const BorderSide(color: AppColors.dreamCloudBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Quiz list or empty state
            if (quizzes.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppBorderRadius.card),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.quiz_outlined,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No custom quizzes yet',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Create a custom mix of categories',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...quizzes.map((quiz) => _buildQuizCard(quiz)),
          ],
        );
      },
    );
  }

  Widget _buildQuizCard(CustomQuiz quiz) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Row(
        children: [
          // Quiz info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quiz.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  quiz.categoriesDisplay,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Edit button
          OutlinedButton(
            onPressed: () => widget.onEditCustomQuiz(quiz.id),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dreamCloudBlue,
              side: const BorderSide(color: AppColors.dreamCloudBlue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}
