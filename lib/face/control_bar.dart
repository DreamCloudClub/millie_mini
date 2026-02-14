import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/providers.dart';
import '../models/models.dart';

class ControlBar extends StatelessWidget {
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onExit;

  const ControlBar({
    super.key,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceProvider>(
      builder: (context, voiceProvider, _) {
        final isPaused = voiceProvider.isPaused;
        
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
              // Refresh button
              _ControlButton(
                icon: Icons.refresh,
                label: 'Refresh',
                onTap: onRefresh,
                buttonColor: Colors.green,
              ),
              // Play/Pause button in middle
              if (!isPaused && voiceProvider.state != VoiceState.sleep)
                _ControlButton(
                  icon: Icons.pause,
                  label: 'Pause',
                  onTap: onPause,
                  buttonColor: Colors.blue,
                ),
              if (isPaused || voiceProvider.state == VoiceState.sleep)
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

