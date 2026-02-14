import 'package:flutter/material.dart';
import '../utils/constants.dart';

enum AppButtonType { primary, secondary, outline, text }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonType type;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;
  final Color? customColor;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.type = AppButtonType.primary,
    this.isLoading = false,
    this.isFullWidth = false,
    this.icon,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;
    
    Color backgroundColor;
    Color foregroundColor;
    Color borderColor;
    
    switch (type) {
      case AppButtonType.primary:
        backgroundColor = customColor ?? AppColors.buttonPrimary;
        foregroundColor = Colors.white;
        borderColor = Colors.transparent;
        break;
      case AppButtonType.secondary:
        backgroundColor = AppColors.buttonSecondary;
        foregroundColor = Colors.white;
        borderColor = Colors.transparent;
        break;
      case AppButtonType.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = customColor ?? AppColors.dreamCloudBlue;
        borderColor = customColor ?? AppColors.dreamCloudBlue;
        break;
      case AppButtonType.text:
        backgroundColor = Colors.transparent;
        foregroundColor = customColor ?? AppColors.dreamCloudBlue;
        borderColor = Colors.transparent;
        break;
    }
    
    if (isDisabled && type != AppButtonType.text) {
      backgroundColor = AppColors.buttonDisabled;
      foregroundColor = Colors.white;
    }

    final buttonContent = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(foregroundColor),
            ),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            label,
            style: AppTextStyles.button.copyWith(
              color: foregroundColor,
              fontSize: 18,
            ),
          ),
        ],
      ],
    );

    if (type == AppButtonType.text) {
      return TextButton(
        onPressed: isLoading ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
        child: buttonContent,
      );
    }

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: type == AppButtonType.outline ? 0 : 2,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
            side: BorderSide(color: borderColor, width: 1.5),
          ),
        ),
        child: buttonContent,
      ),
    );
  }
}

