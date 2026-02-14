import 'package:flutter/material.dart';
import '../utils/constants.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool enabled;
  final Widget? suffixIcon;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final bool darkMode;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.enabled = true,
    this.suffixIcon,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.darkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // Colors based on theme mode
    final labelColor = darkMode ? Colors.white.withOpacity(0.7) : AppColors.textSecondary;
    final textColor = darkMode ? Colors.white : AppColors.textPrimary;
    final hintColor = darkMode ? Colors.white.withOpacity(0.4) : AppColors.textLight;
    final fillColor = darkMode 
        ? (enabled ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.05))
        : (enabled ? Colors.white : Colors.grey.shade100);
    final borderColor = darkMode ? Colors.white.withOpacity(0.2) : AppColors.divider;
    final errorColor = darkMode ? Colors.red.shade300 : AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.label.copyWith(color: labelColor),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          onChanged: onChanged,
          enabled: enabled,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          style: AppTextStyles.bodyLarge.copyWith(color: textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyLarge.copyWith(
              color: hintColor,
            ),
            filled: true,
            fillColor: fillColor,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
              borderSide: const BorderSide(
                color: AppColors.dreamCloudBlue,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
              borderSide: BorderSide(color: errorColor),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
              borderSide: BorderSide(color: errorColor, width: 2),
            ),
            errorStyle: TextStyle(color: errorColor),
          ),
        ),
      ],
    );
  }
}

