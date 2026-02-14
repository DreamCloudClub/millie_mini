import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/services.dart';
import '../services/supabase_service.dart';
import '../services/reminder_scheduler_service.dart';
import 'face_eyes.dart';
import 'face_mouth.dart';
import 'control_bar.dart';

class FacePage extends StatefulWidget {
  final VoidCallback onExit;

  const FacePage({
    super.key,
    required this.onExit,
  });

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage> {
  bool _showControlBar = true; // Start with bars visible
  DateTime? _lastTapTime;
  int _tapCount = 0;
  bool _isStartingSession = false; // Guard to prevent multiple session starts
  bool _sessionStarted = false; // Track if session has been started by user

  @override
  void initState() {
    super.initState();
    // Enable wakelock to keep screen on (allows dimming but prevents sleep)
    WakelockPlus.enable();
    
    // Hide both status bar and navigation bar for full immersive experience on face screen
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    
    // Notify scheduler that we're on the face page
    ReminderSchedulerService.getInstance().setOnFacePage(true);

    // Don't auto-start session - wait for user to press Play
    // Session will start when user presses Play button
  }

  @override
  void dispose() {
    // Notify scheduler that we're leaving the face page
    ReminderSchedulerService.getInstance().setOnFacePage(false);
    
    // Disable wakelock when face page is closed
    WakelockPlus.disable();
    
    // Restore status bar visibility (nav bar stays hidden) when leaving face screen
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    
    // Clean up when widget is disposed
    super.dispose();
  }

  Future<void> _startSession() async {
    // Prevent multiple simultaneous session starts
    if (_isStartingSession) {
      debugPrint('Session start already in progress - skipping');
      return;
    }
    
    _isStartingSession = true;
    
    try {
      final voiceProvider = context.read<VoiceProvider>();
      final agentProvider = context.read<AgentProvider>();
      final personalityProvider = context.read<PersonalityProvider>();
      final authProvider = context.read<AuthProvider>();
      final aiServiceProvider = context.read<AIServiceProvider>();
      final agent = agentProvider.activeAgent;
      
      if (agent != null) {
        final username = authProvider.userProfile?.username ?? 
                        authProvider.userProfile?.firstName ?? 
                        'there';
        final bio = authProvider.userProfile?.bio;
        
        // Get user info for usage tracking
        final userId = authProvider.userProfile?.id;
        final userEmail = authProvider.userProfile?.email;
        
        // Get subscription status from Dream Cloud service
        final dreamCloudService = aiServiceProvider.dreamCloudService;
        final subscriptionStatus = dreamCloudService?.status;
        
        // Get personality prompt
        final personality = personalityProvider.getPersonalityById(agent.personalityId);
        final personalityPrompt = personality?.behaviorPrompt ?? '';
        
        // Ensure any previous session is fully stopped before starting
        await voiceProvider.endSession();
        
        // Wait a moment to ensure everything is stopped
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Start new session with intro message
        await voiceProvider.startSession(
          agent.id,
          agentName: agent.name,
          introMessage: agent.introMessage,
          voice: agent.voice,
          username: username,
          bio: bio,
          personalityPrompt: personalityPrompt,
          aiServiceId: agent.aiServiceId,
          userId: userId,
          userEmail: userEmail,
          subscriptionStatus: subscriptionStatus,
        );
      }
    } finally {
      // Always reset the flag to allow future session starts
      _isStartingSession = false;
    }
  }

  Future<void> _handleTap() async {
    final now = DateTime.now();
    final voiceProvider = context.read<VoiceProvider>();
    
    // Check for double tap (within 300ms)
    if (_lastTapTime != null && 
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _tapCount++;
      if (_tapCount >= 2) {
        // Double tap detected
        _tapCount = 0;
        _lastTapTime = null;
        
        // If in sleep or paused state, wake up/resume
        if (voiceProvider.state == VoiceState.sleep || voiceProvider.state == VoiceState.paused) {
          debugPrint('Double tap detected in ${voiceProvider.state} - waking up/resuming');
          await voiceProvider.resume();
          return;
        }
        
        // Otherwise, toggle pause/play
        _togglePause();
        return;
      }
    } else {
      _tapCount = 1;
    }
    
    _lastTapTime = now;
    
    // Single tap - do nothing (recording is automatic)
    // Only double tap is used for pause/unpause or waking from sleep/paused
  }
  
  Future<void> _togglePause() async {
    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.togglePause();
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
    _hideControlBar(); // Hide bars when playing

    final voiceProvider = context.read<VoiceProvider>();

    // If session hasn't been started yet, start it
    if (!_sessionStarted) {
      _sessionStarted = true;
      await _startSession();
      return;
    }

    // If in sleep state, wake up and activate session
    if (voiceProvider.state == VoiceState.sleep) {
      debugPrint('Play button pressed in sleep mode - waking up');
      await voiceProvider.resume(); // This will activate the pending session
    } else {
      // Normal resume from pause (preserves conversation)
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
      // Get AI service and subscription status
      final aiService = aiServiceProvider.getServiceById(agent.aiServiceId);
      final subscriptionStatus = aiService?.isDreamCloud == true 
          ? aiServiceProvider.dreamCloudService?.status 
          : null;
      
      // Get user info for usage tracking
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.userProfile?.id;
      final userEmail = authProvider.userProfile?.email;
      
      // Check usage limit if using Dream Cloud AI
      if (aiService != null && aiService.isDreamCloud && 
          subscriptionStatus != null && subscriptionStatus.isUsable &&
          userId != null && userEmail != null) {
        try {
          final usageInfo = await UsageTrackingService.getCurrentUsage(
            userId,
            userEmail: userEmail,
            subscriptionStatus: subscriptionStatus,
          );
          
          final tokensUsed = usageInfo['tokens_used'] as int? ?? 0;
          final tokenLimit = usageInfo['token_limit'] as int? ?? 0;
          final tokensRemaining = usageInfo['tokens_remaining'] as int? ?? 0;

          // If limit exceeded, show modal and don't refresh
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
            return; // Don't refresh
          }
        } catch (e) {
          debugPrint('Error checking usage limit (allowing refresh): $e');
          // On error, allow refresh to proceed
        }
      }
      
      // Refresh clears conversation and goes to sleep mode (waits for wake word)
      await voiceProvider.refreshSession(agent.id);
      
      // Wait a moment, then restart session in sleep mode
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Restart session (will start in sleep mode, waiting for wake word/play/double-tap)
      // This sets up the pending session parameters so wake word can activate it
      _sessionStarted = true;
      _startSession();
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

  Future<void> _handleExit() async {
    _hideControlBar(); // Close modal immediately
    
    // Disable wakelock before exiting
    WakelockPlus.disable();
    
    // Restore status bar visibility (nav bar stays hidden) when exiting face screen
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    
    // Ensure session is fully stopped before exiting
    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.endSession();
    
    // Wait a moment to ensure cleanup completes
    await Future.delayed(const Duration(milliseconds: 300));
    
    widget.onExit();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: GestureDetector(
        onTap: _handleTap,
        onLongPress: _handleLongPress,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
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
              
              // Control Bar Overlay
              if (_showControlBar)
                Stack(
                  children: [
                    // Backdrop that closes on tap
                    GestureDetector(
                      onTap: _hideControlBar,
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                      ),
                    ),
                    // Control bar itself - buttons will close modal after action
                    Column(
                      children: [
                        const Spacer(),
                        ControlBar(
                          onPause: _handlePause,
                          onPlay: _handlePlay,
                          onRefresh: _handleRefresh,
                          onExit: _handleExit,
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

