import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class AgentProfilesPage extends StatelessWidget {
  final VoidCallback onBack;
  final void Function(String? agentId) onEditAgent;

  const AgentProfilesPage({
    super.key,
    required this.onBack,
    required this.onEditAgent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Agent Profiles',
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
              onPressed: () => onEditAgent(null),
              icon: const Icon(Icons.add, color: AppColors.dreamCloudBlue),
              label: const Text(
                'Create New Agent',
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
      body: Consumer3<AgentProvider, PersonalityProvider, AIServiceProvider>(
        builder: (context, agentProvider, personalityProvider, aiServiceProvider, _) {
          final agents = agentProvider.agents;

          if (agents.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 64,
                    color: AppColors.textLight,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No agents yet',
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Create Your First Agent',
                    onPressed: () => onEditAgent(null),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: agents.length,
            itemBuilder: (context, index) {
              final agent = agents[index];
              final personality = personalityProvider.getPersonalityById(agent.personalityId);
              final aiService = aiServiceProvider.getServiceById(agent.aiServiceId);

              return _AgentCard(
                agent: agent,
                personality: personality,
                aiService: aiService,
                onActivate: () {
                  agentProvider.setActiveAgent(agent.id);
                },
                onEdit: () => onEditAgent(agent.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final Personality? personality;
  final AIService? aiService;
  final VoidCallback onActivate;
  final VoidCallback onEdit;

  const _AgentCard({
    required this.agent,
    this.personality,
    this.aiService,
    required this.onActivate,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: agent.isActive
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
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Face Preview - larger but square
              FacePreview(
                faceColor: agent.faceColor,
                eyeShape: agent.eyeShape,
                size: 120,
              ),
              const SizedBox(width: AppSpacing.lg),
              // Agent Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: AppTextStyles.heading3.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      aiService?.displayName ?? 'Dream Cloud AI',
                      style: AppTextStyles.bodyMedium.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Voice: ${agent.voice}',
                      style: AppTextStyles.bodyMedium.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Personality: ${personality?.name ?? 'Home'}',
                      style: AppTextStyles.bodyMedium.copyWith(fontSize: 16),
                    ),
                  ],
                ),
              ),
              // Spacer to push buttons to the right
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
                child: const Text('Edit', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          // Active/Activate button in bottom right corner
          Positioned(
            bottom: 0,
            right: 0,
            child: agent.isActive
                ? ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success.withOpacity(0.25),
                      foregroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      disabledBackgroundColor: AppColors.success.withOpacity(0.25),
                      disabledForegroundColor: AppColors.success,
                      elevation: 0,
                      minimumSize: const Size(0, 0), // Allow button to size to content
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: onActivate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange.withOpacity(0.25),
                      foregroundColor: AppColors.primaryOrange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                      minimumSize: const Size(0, 0), // Allow button to size to content
                    ),
                    child: const Text(
                      'Activate',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.visible, // Prevent text wrapping
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
