import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/services.dart';

class DashboardPage extends StatelessWidget {
  final VoidCallback onLaunchMillie;
  final VoidCallback onEditAgentProfile;
  final VoidCallback onEditUserProfile;
  final VoidCallback onEditAIService;
  final VoidCallback onEditAccountSettings;
  final VoidCallback onEditGameSettings;
  final VoidCallback onEditOpenClaw;

  const DashboardPage({
    super.key,
    required this.onLaunchMillie,
    required this.onEditAgentProfile,
    required this.onEditUserProfile,
    required this.onEditAIService,
    required this.onEditAccountSettings,
    required this.onEditGameSettings,
    required this.onEditOpenClaw,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dreamCloudBlue,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              // Header Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppBorderRadius.card),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Millie Mini AI text on left
                    const Text(
                      'Millie Mini AI',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    // Logo in center (clickable)
                    InkWell(
                      onTap: () async {
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
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Image.asset(
                          'assets/icon/logo.png',
                          height: 50,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // Dream Cloud text on right
                    const Text(
                      'Dream Cloud',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Card 1: Agent Profile
              _AgentProfileCard(
                onEdit: onEditAgentProfile,
                onLaunch: onLaunchMillie,
              ),
              const SizedBox(height: AppSpacing.md),

              // Card 2: User Profile
              _UserProfileCard(onEdit: onEditUserProfile),
              const SizedBox(height: AppSpacing.md),

              // Card 3: Game Settings
              _GameSettingsCard(onEdit: onEditGameSettings),
              const SizedBox(height: AppSpacing.md),

              // Card 4: AI Service
              _AIServiceCard(onEdit: onEditAIService),
              const SizedBox(height: AppSpacing.md),

              // Card 5: OpenClaw
              _OpenClawCard(onEdit: onEditOpenClaw),
              const SizedBox(height: AppSpacing.md),

              // Card 6: Account Settings
              _AccountSettingsCard(onEdit: onEditAccountSettings),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentProfileCard extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onLaunch;

  const _AgentProfileCard({
    required this.onEdit,
    required this.onLaunch,
  });

  Future<void> _handleLaunch(
    BuildContext context,
    AIService? aiService,
    VoidCallback onLaunch,
  ) async {
    // Only check usage for Dream Cloud AI service
    if (aiService != null && aiService.isDreamCloud && aiService.status.isUsable) {
      // Get user info
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.userProfile?.id;
      final userEmail = authProvider.userProfile?.email;

      if (userId != null && userEmail != null) {
        try {
          // Check current usage
          final usageInfo = await UsageTrackingService.getCurrentUsage(
            userId,
            userEmail: userEmail,
            subscriptionStatus: aiService.status,
          );
          
          final tokensUsed = usageInfo['tokens_used'] as int? ?? 0;
          final tokenLimit = usageInfo['token_limit'] as int? ?? 0;
          final tokensRemaining = usageInfo['tokens_remaining'] as int? ?? 0;

          // If limit exceeded (no tokens remaining or tokens used >= limit), show modal
          if (tokenLimit > 0 && (tokensRemaining <= 0 || tokensUsed >= tokenLimit)) {
            final subscriptionTier = _getSubscriptionTierName(aiService.status);
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (context) => UsageLimitModal(
                  tokensUsed: tokensUsed,
                  tokenLimit: tokenLimit,
                  subscriptionTier: subscriptionTier,
                ),
              );
            }
            return; // Don't launch
          }
        } catch (e) {
          debugPrint('Error checking usage limit (allowing launch): $e');
          // On error, allow launch to proceed
        }
      }
    }

    // Launch normally if not Dream Cloud, or if within limit
    onLaunch();
  }

  String _getSubscriptionTierName(AIServiceStatus status) {
    switch (status) {
      case AIServiceStatus.holder:
        return 'Holder';
      case AIServiceStatus.basic:
        return 'Basic';
      case AIServiceStatus.pro:
        return 'Pro';
      case AIServiceStatus.active:
        return 'Active';
      case AIServiceStatus.trial:
        return 'Trial';
      default:
        return 'Subscription';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AgentProvider, PersonalityProvider, AIServiceProvider>(
      builder: (context, agentProvider, personalityProvider, aiServiceProvider, _) {
        final agent = agentProvider.activeAgent;
        if (agent == null) {
          return const SizedBox.shrink();
        }

        final personality = personalityProvider.getPersonalityById(agent.personalityId);
        final aiService = aiServiceProvider.getServiceById(agent.aiServiceId);

        return AppCard(
          title: 'Agent Profile',
          onEdit: onEdit,
          child: Column(
            children: [
              // Face Preview
              Center(
                child: FacePreview(
                  faceColor: agent.faceColor,
                  eyeShape: agent.eyeShape,
                  faceImageId: agent.faceImageId,
                  customFaceId: agent.customFaceId,
                  size: 280, // 2x larger
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Agent details
              _DetailRow(
                label: 'Name',
                value: agent.name,
                compactSpacing: true,
              ),
              _DetailRow(
                label: 'Voice',
                value: agent.voice,
                compactSpacing: true,
              ),
              _DetailRow(
                label: 'Personality',
                value: personality?.name ?? 'Home',
                compactSpacing: true,
              ),
              if (aiService != null)
                _DetailRow(
                  label: 'AI Service',
                  value: aiService.displayName,
                  compactSpacing: true,
                ),
              const SizedBox(height: AppSpacing.xl),
              // Launch button
              AppButton(
                label: 'Launch',
                onPressed: () => _handleLaunch(context, aiService, onLaunch),
                isFullWidth: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _UserProfileCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.userProfile;
        if (user == null) {
          return const SizedBox.shrink();
        }

        return AppCard(
          title: 'User Profile',
          onEdit: onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Username', value: user.username, compactSpacing: true),
              if (user.fullName.isNotEmpty)
                _DetailRow(label: 'Full Name', value: user.fullName, compactSpacing: true),
              if (user.pronouns != null && user.pronouns!.isNotEmpty)
                _DetailRow(label: 'Pronouns', value: user.pronouns!, compactSpacing: true),
              if (user.bio != null && user.bio!.isNotEmpty)
                _DetailRow(label: 'Bio', value: user.bio!, compactSpacing: true),
            ],
          ),
        );
      },
    );
  }
}

class _AIServiceCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _AIServiceCard({required this.onEdit});

  Color _getStatusColor(AIServiceStatus status) {
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

  @override
  Widget build(BuildContext context) {
    return Consumer2<AgentProvider, AIServiceProvider>(
      builder: (context, agentProvider, aiServiceProvider, _) {
        final agent = agentProvider.activeAgent;
        final service = agent != null
            ? aiServiceProvider.getServiceById(agent.aiServiceId)
            : aiServiceProvider.dreamCloudService;

        return AppCard(
          title: 'AI Service',
          onEdit: onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service?.displayName ?? 'Dream Cloud AI',
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 18),
              ),
              if (service != null && service.isDreamCloud && service.status != AIServiceStatus.unknown)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    service.status.displayName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 16,
                      color: _getStatusColor(service.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GameSettingsCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _GameSettingsCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameSettingsProvider>(
      builder: (context, gameSettingsProvider, _) {
        final settings = gameSettingsProvider.settings;

        return AppCard(
          title: 'Game Settings',
          onEdit: onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: 'Time Limit',
                value: settings.timeLimit.displayName,
                compactSpacing: true,
              ),
              _DetailRow(
                label: 'Difficulty',
                value: settings.difficulty.displayName,
                compactSpacing: true,
              ),
              _DetailRow(
                label: 'Display Size',
                value: settings.displaySize.displayName,
                compactSpacing: true,
              ),
              _DetailRow(
                label: 'Auto-Play',
                value: settings.autoRecord ? 'On' : 'Off',
                compactSpacing: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OpenClawCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _OpenClawCard({required this.onEdit});

  Color _getStatusColor(OpenClawConnectionState state, bool enabled) {
    if (!enabled) return AppColors.textLight;
    switch (state) {
      case OpenClawConnectionState.connected:
        return AppColors.success;
      case OpenClawConnectionState.connecting:
        return Colors.orange;
      case OpenClawConnectionState.error:
        return AppColors.error;
      case OpenClawConnectionState.disconnected:
        return AppColors.textLight;
    }
  }

  String _getStatusText(OpenClawConnectionState state, bool enabled) {
    if (!enabled) return 'Disabled';
    switch (state) {
      case OpenClawConnectionState.connected:
        return 'Connected';
      case OpenClawConnectionState.connecting:
        return 'Connecting...';
      case OpenClawConnectionState.error:
        return 'Error';
      case OpenClawConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OpenClawProvider>(
      builder: (context, provider, _) {
        return AppCard(
          title: 'OpenClaw',
          onEdit: onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _getStatusColor(provider.connectionState, provider.enabled),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _getStatusText(provider.connectionState, provider.enabled),
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 18,
                      color: _getStatusColor(provider.connectionState, provider.enabled),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (provider.enabled && provider.url.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    provider.url.length > 35
                        ? '${provider.url.substring(0, 35)}...'
                        : provider.url,
                    style: AppTextStyles.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountSettingsCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _AccountSettingsCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Account Settings',
      onEdit: onEdit,
      child: const Text(
        'Manage your account, security, and preferences',
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compactSpacing;

  const _DetailRow({
    required this.label,
    required this.value,
    this.compactSpacing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compactSpacing ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.label.copyWith(fontSize: 16),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

