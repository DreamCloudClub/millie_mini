import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';

class ConversationsPage extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onBrowseTemplates;
  final void Function(String? conversationId) onEditConversation;

  const ConversationsPage({
    super.key,
    required this.onBack,
    required this.onBrowseTemplates,
    required this.onEditConversation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Conversations',
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
            child: OutlinedButton.icon(
              onPressed: () => onEditConversation(null),
              icon: const Icon(Icons.add, color: AppColors.dreamCloudBlue),
              label: const Text(
                'Create Blank',
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
          ),
        ],
      ),
      body: Consumer<ConversationTemplateProvider>(
        builder: (context, provider, _) {
          final templates = provider.templates;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // Browse Templates Card
              _BrowseTemplatesCard(onTap: onBrowseTemplates),
              const SizedBox(height: AppSpacing.lg),

              // My Conversations Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Conversations', style: AppTextStyles.heading3),
                  Text(
                    '${templates.length}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              if (templates.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Center(
                    child: Text(
                      'No conversations yet. Browse templates or create a blank one.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...templates.map((template) => _ConversationCard(
                  template: template,
                  onActivate: () => provider.setActiveTemplate(template.id),
                  onEdit: () => onEditConversation(template.id),
                )),
            ],
          );
        },
      ),
    );
  }
}

class _BrowseTemplatesCard extends StatelessWidget {
  final VoidCallback onTap;

  const _BrowseTemplatesCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final templateCount = ConversationTemplateProvider.starterTemplates.length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
          border: Border.all(color: AppColors.dreamCloudBlue.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.dreamCloudBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.folder_outlined,
                color: AppColors.dreamCloudBlue,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Browse Templates',
                    style: AppTextStyles.heading3,
                  ),
                  Text(
                    '$templateCount template${templateCount == 1 ? '' : 's'} available',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.dreamCloudBlue,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final ConversationTemplate template;
  final VoidCallback onActivate;
  final VoidCallback onEdit;

  const _ConversationCard({
    required this.template,
    required this.onActivate,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: template.isActive
            ? Border.all(color: AppColors.dreamCloudBlue, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.dreamCloudBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.chat_outlined,
              color: AppColors.dreamCloudBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${template.steps.length} step${template.steps.length == 1 ? '' : 's'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
          // Edit/Activate buttons
          Column(
            children: [
              SizedBox(
                width: 80,
                child: OutlinedButton(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dreamCloudBlue,
                    side: const BorderSide(
                      color: AppColors.dreamCloudBlue,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Edit', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: 80,
                child: template.isActive
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs + 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Active',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : OutlinedButton(
                        onPressed: onActivate,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryOrange,
                          side: const BorderSide(
                            color: AppColors.primaryOrange,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Activate', style: TextStyle(fontSize: 13)),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
