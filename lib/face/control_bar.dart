import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../game/lesson_phase.dart';

class ControlBar extends StatelessWidget {
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onExit;
  final VoidCallback? onSkip;
  final VoidCallback? onStart;
  final VoidCallback? onGamePause;
  final VoidCallback? onGameResume;
  final VoidCallback? onRecord;

  const ControlBar({
    super.key,
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
  Widget build(BuildContext context) {
    return Consumer<VoiceProvider>(
      builder: (context, voiceProvider, _) {
        final isPaused = voiceProvider.isPaused;
        final isGameSelected = voiceProvider.isGameSelected;
        final isGameRunning = voiceProvider.isGameRunning;
        final isGamePaused = voiceProvider.isGamePaused;
        final gameController = voiceProvider.gameController;
        final isWaitingForRecord = isGameRunning &&
            !gameController.autoRecord &&
            gameController.phase == LessonPhase.ask;

        return Container(
          margin: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A), // Dark grey
            borderRadius: BorderRadius.circular(AppBorderRadius.large),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // First button: Skip (on game page) or Refresh (otherwise)
              if (onSkip != null)
                _ControlButton(
                  icon: Icons.skip_next,
                  label: 'Skip',
                  onTap: onSkip!,
                  buttonColor: Colors.green,
                )
              else
                _ControlButton(
                  icon: Icons.refresh,
                  label: 'Refresh',
                  onTap: onRefresh,
                  buttonColor: Colors.green,
                ),

              // Middle button: Start/Pause/Play/Record based on state
              if (isGameSelected && onStart != null)
                // Category selected, show Start button
                _ControlButton(
                  icon: Icons.play_arrow,
                  label: 'Start',
                  onTap: onStart!,
                  buttonColor: Colors.blue,
                )
              else if (isWaitingForRecord && onRecord != null)
                // Waiting for user to submit answer (auto-record off)
                _ControlButton(
                  icon: Icons.play_arrow,
                  label: 'Answer',
                  onTap: onRecord!,
                  buttonColor: Colors.blue,
                )
              else if (isGameRunning)
                // Game running - show Pause or Resume
                if (isGamePaused && onGameResume != null)
                  _ControlButton(
                    icon: Icons.play_arrow,
                    label: 'Play',
                    onTap: onGameResume!,
                    buttonColor: Colors.blue,
                  )
                else if (onGamePause != null)
                  _ControlButton(
                    icon: Icons.pause,
                    label: 'Pause',
                    onTap: onGamePause!,
                    buttonColor: Colors.blue,
                  )
                else
                  _ControlButton(
                    icon: Icons.pause,
                    label: 'Pause',
                    onTap: onPause,
                    buttonColor: Colors.blue,
                  )
              else if (onStart != null)
                // On game page but no category selected - show Play (not Wake)
                _ControlButton(
                  icon: Icons.play_arrow,
                  label: 'Play',
                  onTap: onPlay,
                  buttonColor: Colors.blue,
                )
              else
                // Normal conversation mode
                if (!isPaused && voiceProvider.state != VoiceState.sleep)
                  _ControlButton(
                    icon: Icons.pause,
                    label: 'Pause',
                    onTap: onPause,
                    buttonColor: Colors.blue,
                  )
                else
                  _ControlButton(
                    icon: Icons.play_arrow,
                    label: voiceProvider.state == VoiceState.sleep ? 'Wake' : 'Play',
                    onTap: onPlay,
                    buttonColor: Colors.blue,
                  ),

              // Exit button - primary orange
              _ControlButton(
                icon: Icons.close,
                label: 'Exit',
                onTap: onExit,
                buttonColor: AppColors.primaryOrange,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color buttonColor;
  final Color iconColor;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.buttonColor,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: buttonColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

