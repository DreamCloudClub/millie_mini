import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/services.dart';
import '../services/supabase_service.dart';

class AIServicesPage extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onEditDreamCloud;
  final void Function(String? serviceId) onEditCustomService;

  const AIServicesPage({
    super.key,
    required this.onBack,
    required this.onEditDreamCloud,
    required this.onEditCustomService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'AI Account Settings',
            style: AppTextStyles.heading2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: OutlinedButton(
              onPressed: () async {
                try {
                  final uri = Uri.parse('https://dreamcloudclub.org/my-account/');
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                } catch (e) {
                  debugPrint('Error launching URL: $e');
                  // Try alternative approach
                  try {
                    final uri = Uri.parse('https://dreamcloudclub.org/my-account/');
                    await launchUrl(uri);
                  } catch (e2) {
                    debugPrint('Error launching URL (fallback): $e2');
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.dreamCloudBlue,
                side: const BorderSide(
                  color: AppColors.dreamCloudBlue,
                  width: 1.5,
                ),
                backgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Manage Subscription',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<AIServiceProvider>(
        builder: (context, aiProvider, _) {
          final dreamCloud = aiProvider.dreamCloudService;
          final customServices = aiProvider.customServices;

          Color getStatusColor(AIServiceStatus status) {
            switch (status) {
              case AIServiceStatus.holder:
                return Colors.amber;
              case AIServiceStatus.active:
                return AppColors.success;
              case AIServiceStatus.trial:
                return Colors.blue;
              case AIServiceStatus.pending:
                return Colors.orange;
              case AIServiceStatus.expired:
              case AIServiceStatus.inactive:
              case AIServiceStatus.notFound:
                return AppColors.error;
              default:
                return AppColors.textLight;
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dream Cloud AI Section
                _DreamCloudServiceCard(
                  dreamCloud: dreamCloud,
                  onEdit: onEditDreamCloud,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Custom AI Accounts Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Custom AI Accounts',
                      style: AppTextStyles.heading3,
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onEditCustomService(null),
                      icon: const Icon(Icons.add, size: 18, color: AppColors.dreamCloudBlue),
                      label: const Text(
                        'Add',
                        style: TextStyle(
                          color: AppColors.dreamCloudBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dreamCloudBlue,
                        side: const BorderSide(
                          color: AppColors.dreamCloudBlue,
                          width: 1.5,
                        ),
                        backgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                if (customServices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppBorderRadius.card),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.api_outlined,
                            size: 48,
                            color: AppColors.textLight,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'No custom AI services',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Add OpenAI, Gemini, or Anthropic accounts',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...customServices.map((service) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ServiceCard(
                      title: service.displayName,
                      subtitle: service.type.displayName,
                      onEdit: () => onEditCustomService(service.id),
                    ),
                  )),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DreamCloudServiceCard extends StatelessWidget {
  final AIService? dreamCloud;
  final VoidCallback onEdit;

  const _DreamCloudServiceCard({
    required this.dreamCloud,
    required this.onEdit,
  });

  Color _getStatusColor(AIServiceStatus status) {
    switch (status) {
      case AIServiceStatus.holder:
        return Colors.amber;
      case AIServiceStatus.basic:
        return AppColors.success;
      case AIServiceStatus.pro:
        return Colors.blue;
      case AIServiceStatus.active:
        return AppColors.success;
      case AIServiceStatus.trial:
        return Colors.blue;
      case AIServiceStatus.pending:
        return Colors.orange;
      case AIServiceStatus.expired:
      case AIServiceStatus.inactive:
      case AIServiceStatus.notFound:
        return AppColors.error;
      default:
        return AppColors.textLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final userId = authProvider.userProfile?.id;
        final userEmail = authProvider.userProfile?.email;
        final status = dreamCloud?.status;
        final isUsable = status != null && status.isUsable;

        return FutureBuilder<Map<String, dynamic>>(
          future: userId != null && isUsable
              ? UsageTrackingService.getCurrentUsage(
                  userId,
                  userEmail: userEmail,
                  subscriptionStatus: status,
                )
              : Future.value({
                  'tokens_used': 0,
                  'token_limit': 0,
                  'tokens_remaining': 0,
                }),
          builder: (context, snapshot) {
            final tokensUsed = snapshot.data?['tokens_used'] as int? ?? 0;
            final tokenLimit = snapshot.data?['token_limit'] as int? ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo
                      Container(
                        width: 100,
                        height: 100,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppBorderRadius.small),
                          border: Border.all(
                            color: AppColors.dreamCloudBlue,
                            width: 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppBorderRadius.small),
                          child: Image.asset(
                            'assets/icon/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      // Service Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dream Cloud AI Account',
                              style: AppTextStyles.heading3.copyWith(fontSize: 20),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              status != null && status != AIServiceStatus.unknown
                                  ? status.displayName
                                  : 'Not configured',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 16,
                                color: status != null && status != AIServiceStatus.unknown
                                    ? _getStatusColor(status)
                                    : AppColors.textLight,
                              ),
                            ),
                            // Usage info (only show if subscription is usable and we have data)
                            if (isUsable && tokenLimit > 0) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                '${_formatTokens(tokensUsed)} / ${_formatTokens(tokenLimit)} tokens used',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Spacer to push button to the right
                      const SizedBox(width: 100),
                    ],
                  ),
                  // Edit button in top right corner
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SizedBox(
                      width: 90,
                      child: OutlinedButton(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dreamCloudBlue,
                          side: const BorderSide(
                            color: AppColors.dreamCloudBlue,
                            width: 1.5,
                          ),
                          backgroundColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Edit',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      final millions = tokens / 1000000;
      // Remove .0 for whole numbers
      return millions % 1 == 0 
          ? '${millions.toInt()}M'
          : '${millions.toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      final thousands = tokens / 1000;
      // Remove .0 for whole numbers
      return thousands % 1 == 0 
          ? '${thousands.toInt()}K'
          : '${thousands.toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }
}

class _ServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final VoidCallback onEdit;
  final bool isDreamCloud;

  const _ServiceCard({
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.onEdit,
    this.isDreamCloud = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo or Icon
              isDreamCloud
                  ? Container(
                      width: 100,
                      height: 100,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                        border: Border.all(
                          color: AppColors.dreamCloudBlue,
                          width: 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                        child: Image.asset(
                          'assets/icon/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.dreamCloudBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                      ),
                      child: const Icon(
                        Icons.cloud_outlined,
                        color: AppColors.dreamCloudBlue,
                      ),
                    ),
              const SizedBox(width: AppSpacing.lg),
              // Service Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.heading3.copyWith(
                        fontSize: isDreamCloud ? 20 : 22,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 16,
                        color: subtitleColor ?? AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Spacer to push button to the right
              const SizedBox(width: 100),
            ],
          ),
          // Edit button in top right corner
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 90,
              child: OutlinedButton(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dreamCloudBlue,
                  side: const BorderSide(
                    color: AppColors.dreamCloudBlue,
                    width: 1.5,
                  ),
                  backgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
