import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_settings_provider.dart';
import '../models/game_settings.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class GameSettingsEditPage extends StatefulWidget {
  final VoidCallback onSaved;

  const GameSettingsEditPage({
    super.key,
    required this.onSaved,
  });

  @override
  State<GameSettingsEditPage> createState() => _GameSettingsEditPageState();
}

class _GameSettingsEditPageState extends State<GameSettingsEditPage> {
  TimeLimit _timeLimit = TimeLimit.none;
  GameDifficulty _difficulty = GameDifficulty.medium;
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
      ));

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Game settings saved'),
          backgroundColor: AppColors.success,
        ),
      );

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
          AppSpacing.md,
        ),
        child: Container(
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
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Save Settings',
                onPressed: _isLoading ? null : _handleSave,
                isLoading: _isLoading,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
