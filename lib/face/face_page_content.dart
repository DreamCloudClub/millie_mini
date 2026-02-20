import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/services.dart';
import '../services/custom_face_service.dart';
import '../services/image_cache_service.dart';
import 'face_eyes.dart';
import 'face_mouth.dart';
import 'control_bar.dart';

/// Face page content for use within ConversationPage's PageView
/// Session management is handled by the parent ConversationPage
class FacePageContent extends StatefulWidget {
  final VoidCallback onExit;
  final VoidCallback onNavigateToGame;
  final VoidCallback onNavigateToChat;
  final VoidCallback onNavigateToReports;
  final VoidCallback onNavigateToNotes;
  final VoidCallback onNavigateToSchedule;
  final Future<void> Function() onRefreshSession;

  const FacePageContent({
    super.key,
    required this.onExit,
    required this.onNavigateToGame,
    required this.onNavigateToChat,
    required this.onNavigateToReports,
    required this.onNavigateToNotes,
    required this.onNavigateToSchedule,
    required this.onRefreshSession,
  });

  @override
  State<FacePageContent> createState() => _FacePageContentState();
}

class _FacePageContentState extends State<FacePageContent> {
  bool _showControlBar = true; // Start with bars visible
  DateTime? _lastTapTime;
  int _tapCount = 0;

  Future<void> _handleTap() async {
    final now = DateTime.now();
    final voiceProvider = context.read<VoiceProvider>();

    // Check for double tap (within 300ms)
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _tapCount++;
      if (_tapCount >= 2) {
        _tapCount = 0;
        _lastTapTime = null;

        // If in sleep or paused state, wake up/resume
        if (voiceProvider.state == VoiceState.sleep ||
            voiceProvider.state == VoiceState.paused) {
          debugPrint('Double tap detected in ${voiceProvider.state} - waking up/resuming');
          await voiceProvider.resume();
          return;
        }

        // Otherwise, toggle pause/play
        await voiceProvider.togglePause();
        return;
      }
    } else {
      _tapCount = 1;
    }

    _lastTapTime = now;
  }

  void _handleLongPress() {
    setState(() {
      _showControlBar = true;
    });
  }

  void _hideControlBar() {
    setState(() {
      _showControlBar = false;
    });
  }

  Future<void> _handlePause() async {
    // Keep bars visible when pausing
    await context.read<VoiceProvider>().pause();
  }

  Future<void> _handlePlay() async {
    _hideControlBar();
    final voiceProvider = context.read<VoiceProvider>();

    if (voiceProvider.state == VoiceState.sleep) {
      await voiceProvider.resume();
    } else {
      await voiceProvider.resume();
    }
  }

  Future<void> _handleRefresh() async {
    // Keep bars visible when refreshing

    final agentProvider = context.read<AgentProvider>();
    final voiceProvider = context.read<VoiceProvider>();
    final aiServiceProvider = context.read<AIServiceProvider>();
    final agent = agentProvider.activeAgent;

    if (agent != null) {
      final aiService = aiServiceProvider.getServiceById(agent.aiServiceId);
      final subscriptionStatus = aiService?.isDreamCloud == true
          ? aiServiceProvider.dreamCloudService?.status
          : null;

      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.userProfile?.id;
      final userEmail = authProvider.userProfile?.email;

      // Check usage limit if using Dream Cloud AI
      if (aiService != null &&
          aiService.isDreamCloud &&
          subscriptionStatus != null &&
          subscriptionStatus.isUsable &&
          userId != null &&
          userEmail != null) {
        try {
          final usageInfo = await UsageTrackingService.getCurrentUsage(
            userId,
            userEmail: userEmail,
            subscriptionStatus: subscriptionStatus,
          );

          final tokensUsed = usageInfo['tokens_used'] as int? ?? 0;
          final tokenLimit = usageInfo['token_limit'] as int? ?? 0;
          final tokensRemaining = usageInfo['tokens_remaining'] as int? ?? 0;

          if (tokenLimit > 0 && (tokensRemaining <= 0 || tokensUsed >= tokenLimit)) {
            final subscriptionTier = _getSubscriptionTierName(subscriptionStatus);
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => UsageLimitModal(
                  tokensUsed: tokensUsed,
                  tokenLimit: tokenLimit,
                  subscriptionTier: subscriptionTier,
                ),
              );
            }
            return;
          }
        } catch (e) {
          debugPrint('Error checking usage limit (allowing refresh): $e');
        }
      }

      await voiceProvider.refreshSession(agent.id);
      await Future.delayed(const Duration(milliseconds: 500));
      await widget.onRefreshSession();
    }
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

  void _handleNavigateToGame() {
    _hideControlBar();
    widget.onNavigateToGame();
  }

  void _handleNavigateToChat() {
    _hideControlBar();
    widget.onNavigateToChat();
  }

  void _handleNavigateToReports() {
    _hideControlBar();
    widget.onNavigateToReports();
  }

  void _handleNavigateToNotes() {
    _hideControlBar();
    widget.onNavigateToNotes();
  }

  void _handleNavigateToSchedule() {
    _hideControlBar();
    widget.onNavigateToSchedule();
  }

  Widget _buildFaceImageContent(
    BuildContext context,
    Agent agent,
    VoiceProvider voiceProvider,
    double screenW,
    double screenH,
  ) {
    final faceImageProvider = context.read<FaceImageProvider>();
    final faceImage = faceImageProvider.getById(agent.faceImageId);

    if (faceImage == null) {
      // Fallback to robot face if image not found
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 1),
          FaceEyes(
            faceColor: agent.faceColor,
            eyeShape: agent.eyeShape,
            faceState: voiceProvider.faceState,
            screenWidth: screenW,
            screenHeight: screenH,
          ),
          SizedBox(height: screenH * 0.12),
          FaceMouth(
            faceState: voiceProvider.faceState,
            screenWidth: screenW,
            faceColor: agent.faceColor,
          ),
          const Spacer(flex: 1),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Text(
              voiceProvider.state.statusText,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
        ],
      );
    }

    final localPath = ImageCacheService.getFaceLocalPath(faceImage.imageUrl);

    return Stack(
      children: [
        // Full screen face image
        Positioned.fill(
          child: localPath != null
              ? Image.file(
                  File(localPath),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => _buildFallbackImage(screenW),
                )
              : faceImage.imageUrl.isNotEmpty
                  ? Image.network(
                      faceImage.imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => _buildFallbackImage(screenW),
                    )
                  : _buildFallbackImage(screenW),
        ),

        // Status text at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.lg,
          child: Text(
            voiceProvider.state.statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackImage(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade800,
      child: const Icon(
        Icons.pets,
        color: Colors.white54,
        size: 80,
      ),
    );
  }

  Widget _buildCustomFaceContent(
    BuildContext context,
    Agent agent,
    VoiceProvider voiceProvider,
  ) {
    return FutureBuilder<String?>(
      future: CustomFaceService.getLocalPath(agent.customFaceId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }

        final localPath = snapshot.data;
        if (localPath == null) {
          // Fallback to robot face if custom face not found
          return _buildRobotFaceFallback(agent, voiceProvider);
        }

        return Stack(
          children: [
            // Full screen custom face image
            Positioned.fill(
              child: Image.file(
                File(localPath),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) =>
                    _buildRobotFaceFallback(agent, voiceProvider),
              ),
            ),

            // Status text at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.lg,
              child: Text(
                voiceProvider.state.statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRobotFaceFallback(Agent agent, VoiceProvider voiceProvider) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 1),
        FaceEyes(
          faceColor: agent.faceColor,
          eyeShape: agent.eyeShape,
          faceState: voiceProvider.faceState,
          screenWidth: screenW,
          screenHeight: screenH,
        ),
        SizedBox(height: screenH * 0.12),
        FaceMouth(
          faceState: voiceProvider.faceState,
          screenWidth: screenW,
          faceColor: agent.faceColor,
        ),
        const Spacer(flex: 1),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Text(
            voiceProvider.state.statusText,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return GestureDetector(
      onTap: _handleTap,
      onLongPress: _handleLongPress,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Main Face Content
          Center(
            child: Consumer2<VoiceProvider, AgentProvider>(
              builder: (context, voiceProvider, agentProvider, _) {
                final agent = agentProvider.activeAgent;
                final faceState = voiceProvider.faceState;

                if (agent == null) {
                  return const SizedBox.shrink();
                }

                // Check if agent uses a custom face (local AI-generated)
                if (agent.usesCustomFace) {
                  return _buildCustomFaceContent(
                    context,
                    agent,
                    voiceProvider,
                  );
                }

                // Check if agent uses a face image (animal face from Supabase)
                if (agent.usesFaceImage) {
                  return _buildFaceImageContent(
                    context,
                    agent,
                    voiceProvider,
                    screenW,
                    screenH,
                  );
                }

                // Default robot face
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 1),

                    // Eyes
                    FaceEyes(
                      faceColor: agent.faceColor,
                      eyeShape: agent.eyeShape,
                      faceState: faceState,
                      screenWidth: screenW,
                      screenHeight: screenH,
                    ),

                    SizedBox(height: screenH * 0.12),

                    // Mouth
                    FaceMouth(
                      faceState: faceState,
                      screenWidth: screenW,
                      faceColor: agent.faceColor,
                    ),

                    const Spacer(flex: 1),

                    // Status text
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Text(
                        voiceProvider.state.statusText,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Control Bar Overlay (appears on long press)
          if (_showControlBar)
            Stack(
              children: [
                // Backdrop
                GestureDetector(
                  onTap: _hideControlBar,
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
                // Top and bottom bars
                Column(
                  children: [
                    // Top Nav Bar
                    SafeArea(
                      bottom: false,
                      child: _TopNavBar(
                        onNavigateToGame: _handleNavigateToGame,
                        onNavigateToChat: _handleNavigateToChat,
                        onNavigateToReports: _handleNavigateToReports,
                        onNavigateToNotes: _handleNavigateToNotes,
                        onNavigateToSchedule: _handleNavigateToSchedule,
                      ),
                    ),
                    const Spacer(),
                    // Bottom Control Bar
                    SafeArea(
                      top: false,
                      child: ControlBar(
                        onPause: _handlePause,
                        onPlay: _handlePlay,
                        onRefresh: _handleRefresh,
                        onExit: widget.onExit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Top navigation bar matching bottom control bar style
class _TopNavBar extends StatelessWidget {
  final VoidCallback onNavigateToGame;
  final VoidCallback onNavigateToChat;
  final VoidCallback onNavigateToReports;
  final VoidCallback onNavigateToNotes;
  final VoidCallback onNavigateToSchedule;

  const _TopNavBar({
    required this.onNavigateToGame,
    required this.onNavigateToChat,
    required this.onNavigateToReports,
    required this.onNavigateToNotes,
    required this.onNavigateToSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A), // Dark grey matching ControlBar
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
          _NavButton(
            icon: Icons.mood_outlined,
            label: 'Games',
            onTap: onNavigateToGame,
          ),
          _NavButton(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            onTap: onNavigateToChat,
          ),
          _NavButton(
            icon: Icons.article_outlined,
            label: 'Reports',
            onTap: onNavigateToReports,
          ),
          _NavButton(
            icon: Icons.note_alt_outlined,
            label: 'Notes',
            onTap: onNavigateToNotes,
          ),
          _NavButton(
            icon: Icons.schedule,
            label: 'Schedule',
            onTap: onNavigateToSchedule,
          ),
        ],
      ),
    );
  }
}

/// Grey circular navigation button matching ControlBar button style
class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
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
              color: Colors.grey.shade600,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
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

