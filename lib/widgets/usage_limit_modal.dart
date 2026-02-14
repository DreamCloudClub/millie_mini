import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// Modal dialog shown when user exceeds their monthly token limit
class UsageLimitModal extends StatelessWidget {
  final int tokensUsed;
  final int tokenLimit;
  final String subscriptionTier;
  
  const UsageLimitModal({
    super.key,
    required this.tokensUsed,
    required this.tokenLimit,
    required this.subscriptionTier,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Monthly Limit Exceeded',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have exceeded your monthly token limit for your $subscriptionTier subscription.',
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'To continue using Dream Cloud AI, you can:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildOption(
            icon: Icons.upgrade,
            text: 'Upgrade to Pro for 1M tokens/month',
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildOption(
            icon: Icons.history,
            text: 'Wait until next month when your limit resets',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            // Navigate to subscription management
            final uri = Uri.parse('https://dreamcloudclub.org/my-account/');
            try {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            } catch (e) {
              debugPrint('Error launching URL: $e');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.dreamCloudBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Manage Subscription'),
        ),
      ],
    );
  }

  Widget _buildOption({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

