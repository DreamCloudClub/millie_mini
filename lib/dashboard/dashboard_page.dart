import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';
import '../services/openclaw_service.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class DashboardPage extends StatelessWidget {
  final VoidCallback onLaunchMillie;
  final void Function(String templateId) onLaunchKiosk;
  final VoidCallback onEditAgentProfile;
  final VoidCallback onEditUserProfile;
  final VoidCallback onEditAIService;
  final VoidCallback onEditBrain;
  final VoidCallback onEditDeviceSettings;
  final VoidCallback onEditConversations;
  final VoidCallback onEditInventory;
  final VoidCallback onViewReports;

  const DashboardPage({
    super.key,
    required this.onLaunchMillie,
    required this.onLaunchKiosk,
    required this.onEditAgentProfile,
    required this.onEditUserProfile,
    required this.onEditAIService,
    required this.onEditBrain,
    required this.onEditDeviceSettings,
    required this.onEditConversations,
    required this.onEditInventory,
    required this.onViewReports,
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
                    // Millie Mini AI text on left (clickable)
                    InkWell(
                      onTap: () async {
                        try {
                          final uri = Uri.parse('https://milliebot.ai');
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          debugPrint('Error launching URL: $e');
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: const Text(
                        'Millie Mini AI',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // Logo in center (clickable)
                    InkWell(
                      onTap: () async {
                        try {
                          final uri = Uri.parse('https://dreamcloudclub.org');
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          debugPrint('Error launching URL: $e');
                          // Try alternative approach
                          try {
                            final uri = Uri.parse('https://dreamcloudclub.org');
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
                    // Dream Cloud text on right (clickable)
                    InkWell(
                      onTap: () async {
                        try {
                          final uri = Uri.parse('https://dreamcloudclub.org');
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          debugPrint('Error launching URL: $e');
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: const Text(
                        'Dream Cloud',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
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
                onLaunchKiosk: onLaunchKiosk,
              ),
              const SizedBox(height: AppSpacing.md),

              // Card 2: User Profile
              _UserProfileCard(onEdit: onEditUserProfile),
              const SizedBox(height: AppSpacing.md),

              // Card 3: Conversations
              _ConversationsCard(onEdit: onEditConversations),
              const SizedBox(height: AppSpacing.md),

              // Card 4: Reports
              _ReportsCard(onView: onViewReports),
              const SizedBox(height: AppSpacing.md),

              // Card 5: Inventory
              _InventoryCard(onEdit: onEditInventory),
              const SizedBox(height: AppSpacing.md),

              // Card 6: AI Service
              _AIServiceCard(onEdit: onEditAIService),
              const SizedBox(height: AppSpacing.md),

              // Card 7: Open Claw
              _BrainCard(onEdit: onEditBrain),
              const SizedBox(height: AppSpacing.md),

              // Card 8: Device Settings
              _DeviceSettingsCard(onEdit: onEditDeviceSettings),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentProfileCard extends StatefulWidget {
  final VoidCallback onEdit;
  final VoidCallback onLaunch;
  final void Function(String templateId) onLaunchKiosk;

  const _AgentProfileCard({
    required this.onEdit,
    required this.onLaunch,
    required this.onLaunchKiosk,
  });

  @override
  State<_AgentProfileCard> createState() => _AgentProfileCardState();
}

class _AgentProfileCardState extends State<_AgentProfileCard> {
  int _displayIndex = 0;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<AgentProvider, PersonalityProvider>(
      builder: (context, agentProvider, personalityProvider, _) {
        final agents = agentProvider.agents;
        final activeAgent = agentProvider.activeAgent;

        if (agents.isEmpty || activeAgent == null) {
          return const SizedBox.shrink();
        }

        // Initialize display index to active agent on first build
        if (!_initialized) {
          final activeIndex = agents.indexWhere((a) => a.id == activeAgent.id);
          if (activeIndex != -1) {
            _displayIndex = activeIndex;
          }
          _initialized = true;
        }

        // Clamp display index to valid range
        if (_displayIndex >= agents.length) {
          _displayIndex = agents.length - 1;
        }

        final agent = agents[_displayIndex];
        final personality =
            personalityProvider.getPersonalityById(agent.personalityId);

        void goToPrevious() {
          setState(() {
            _displayIndex = (_displayIndex - 1 + agents.length) % agents.length;
          });
        }

        void goToNext() {
          setState(() {
            _displayIndex = (_displayIndex + 1) % agents.length;
          });
        }

        void goToIndex(int index) {
          if (index >= 0 && index < agents.length) {
            setState(() {
              _displayIndex = index;
            });
          }
        }

        // Calculate face size based on screen width
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = screenWidth - 32 - 16;
        final faceSize = (availableWidth - 96) * 0.75;

        return AppCard(
          title: 'Agent Profile',
          onEdit: widget.onEdit,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, AppSpacing.lg),
          child: Column(
            children: [
              // Face with arrows (arrows centered on face only)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Left arrow
                  if (agents.length > 1)
                    GestureDetector(
                      onTap: goToPrevious,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.dreamCloudBlue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          color: AppColors.dreamCloudBlue,
                          size: 28,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 40),

                  const SizedBox(width: 16),

                  // Face Preview only
                  FacePreview(
                    faceColor: agent.faceColor,
                    eyeShape: agent.eyeShape,
                    faceImageId: agent.faceImageId,
                    customFaceId: agent.customFaceId,
                    size: faceSize,
                  ),

                  const SizedBox(width: 16),

                  // Right arrow
                  if (agents.length > 1)
                    GestureDetector(
                      onTap: goToNext,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.dreamCloudBlue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right,
                          color: AppColors.dreamCloudBlue,
                          size: 28,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Agent name
              Text(
                agent.name,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Voice + Personality
              Text(
                '${agent.voice} • ${personality?.name ?? 'Home'}',
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 16,
                  color: AppColors.textLight,
                ),
              ),

              // Page indicator dots
              if (agents.length > 1) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(agents.length, (index) {
                    return GestureDetector(
                      onTap: () => goToIndex(index),
                      child: Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _displayIndex
                              ? AppColors.dreamCloudBlue
                              : AppColors.textLight.withValues(alpha: 0.3),
                        ),
                      ),
                    );
                  }),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // Launch buttons row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Consumer<ConversationTemplateProvider>(
                  builder: (context, templateProvider, _) {
                    final activeTemplate = templateProvider.activeTemplate;

                    return Row(
                      children: [
                        // Main Launch button
                        Expanded(
                          child: AppButton(
                            label: 'Launch',
                            onPressed: () {
                              // Activate this agent then launch
                              agentProvider.setActiveAgent(agent.id);
                              widget.onLaunch();
                            },
                            isFullWidth: true,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Kiosk Launch button
                        Expanded(
                          child: AppButton(
                            label: 'Kiosk',
                            onPressed: activeTemplate != null
                                ? () {
                                    agentProvider.setActiveAgent(agent.id);
                                    widget.onLaunchKiosk(activeTemplate.id);
                                  }
                                : null,
                            isFullWidth: true,
                            customColor: activeTemplate != null
                                ? AppColors.dreamCloudBlue
                                : AppColors.textLight,
                          ),
                        ),
                      ],
                    );
                  },
                ),
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
              _DetailRow(
                  label: 'Username', value: user.username, compactSpacing: true),
              if (user.fullName.isNotEmpty)
                _DetailRow(
                    label: 'Full Name',
                    value: user.fullName,
                    compactSpacing: true),
              if (user.pronouns != null && user.pronouns!.isNotEmpty)
                _DetailRow(
                    label: 'Pronouns',
                    value: user.pronouns!,
                    compactSpacing: true),
              if (user.bio != null && user.bio!.isNotEmpty)
                _DetailRow(
                    label: 'Bio', value: user.bio!, compactSpacing: true),
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AIServiceProvider>(
      builder: (context, aiServiceProvider, _) {
        final hasOpenAI = aiServiceProvider.hasOpenAIKey;

        return AppCard(
          title: 'AI Service',
          onEdit: onEdit,
          child: Row(
            children: [
              Icon(
                hasOpenAI ? Icons.check_circle : Icons.warning,
                color: hasOpenAI ? AppColors.success : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                hasOpenAI ? 'OpenAI API Key configured' : 'OpenAI API Key required',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 16,
                  color: hasOpenAI ? AppColors.textPrimary : Colors.orange,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BrainCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _BrainCard({required this.onEdit});

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
          title: 'Open Claw',
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
                      color:
                          _getStatusColor(provider.connectionState, provider.enabled),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _getStatusText(provider.connectionState, provider.enabled),
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 18,
                      color: _getStatusColor(
                          provider.connectionState, provider.enabled),
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

class _DeviceSettingsCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _DeviceSettingsCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Device Settings',
      onEdit: onEdit,
      child: Row(
        children: [
          Icon(
            Icons.phonelink_setup,
            color: AppColors.dreamCloudBlue,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Manage device permissions',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationsCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _ConversationsCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationTemplateProvider>(
      builder: (context, provider, _) {
        final activeTemplate = provider.activeTemplate;
        final templateCount = provider.templates.length;

        return AppCard(
          title: 'Conversations',
          onEdit: onEdit,
          child: Row(
            children: [
              Icon(
                Icons.chat_outlined,
                color: AppColors.dreamCloudBlue,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  activeTemplate != null
                      ? 'Active: ${activeTemplate.name}'
                      : 'No active conversation',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (templateCount > 0)
                Text(
                  '$templateCount configured',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textLight,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportsCard extends StatelessWidget {
  final VoidCallback onView;

  const _ReportsCard({required this.onView});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationReportProvider>(
      builder: (context, provider, _) {
        final reportCount = provider.completedReports.length;

        return AppCard(
          title: 'Reports',
          onEdit: onView,
          child: Row(
            children: [
              Icon(
                Icons.assessment_outlined,
                color: AppColors.dreamCloudBlue,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                reportCount == 0
                    ? 'No reports yet'
                    : '$reportCount completed report${reportCount == 1 ? '' : 's'}',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final VoidCallback onEdit;

  const _InventoryCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, provider, _) {
        final count = provider.items.length;
        final needsAttention = provider.lowStockCount + provider.outOfStockCount;

        return AppCard(
          title: 'Inventory',
          onEdit: onEdit,
          child: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: AppColors.dreamCloudBlue,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  count == 0
                      ? 'No products loaded'
                      : '$count product${count == 1 ? '' : 's'} with store locations',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (needsAttention > 0)
                Text(
                  '$needsAttention low or out of stock',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryOrange,
                  ),
                ),
            ],
          ),
        );
      },
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
