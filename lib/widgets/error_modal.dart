import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'app_button.dart';

class ErrorModal extends StatelessWidget {
  final String title;
  final String message;
  final bool showAISettingsButton;
  final bool showAppSettingsButton;
  final VoidCallback? onDismiss;
  final VoidCallback? onGoToAISettings;
  final VoidCallback? onGoToAppSettings;

  const ErrorModal({
    super.key,
    required this.title,
    required this.message,
    this.showAISettingsButton = false,
    this.showAppSettingsButton = false,
    this.onDismiss,
    this.onGoToAISettings,
    this.onGoToAppSettings,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    bool showAISettingsButton = false,
    bool showAppSettingsButton = false,
    VoidCallback? onGoToAISettings,
    VoidCallback? onGoToAppSettings,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ErrorModal(
        title: title,
        message: message,
        showAISettingsButton: showAISettingsButton,
        showAppSettingsButton: showAppSettingsButton,
        onDismiss: () => Navigator.of(context).pop(),
        onGoToAISettings: onGoToAISettings != null
            ? () {
                Navigator.of(context).pop();
                onGoToAISettings();
              }
            : null,
        onGoToAppSettings: onGoToAppSettings != null
            ? () {
                Navigator.of(context).pop();
                onGoToAppSettings();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.large),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTextStyles.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (showAISettingsButton && onGoToAISettings != null) ...[
              AppButton(
                label: 'Go to AI Service Settings',
                onPressed: onGoToAISettings,
                type: AppButtonType.outline,
                isFullWidth: true,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (showAppSettingsButton && onGoToAppSettings != null) ...[
              AppButton(
                label: 'Open App Settings',
                onPressed: onGoToAppSettings,
                type: AppButtonType.outline,
                isFullWidth: true,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            AppButton(
              label: 'Dismiss',
              onPressed: onDismiss,
              isFullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

