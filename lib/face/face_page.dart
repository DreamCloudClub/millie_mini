import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../services/services.dart';
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
  bool _isStartingSession = false;
  bool _sessionStarted = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );

    ReminderSchedulerService.getInstance().setOnFacePage(true);
  }

  @override
  void dispose() {
    ReminderSchedulerService.getInstance().setOnFacePage(false);
    WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );

    super.dispose();
  }

  Future<void> _startSession() async {
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
      final agent = agentProvider.activeAgent;

      if (agent != null) {
        final username = authProvider.userProfile?.username ??
            authProvider.userProfile?.firstName ??
            'there';
        final bio = authProvider.userProfile?.bio;
        final userId = authProvider.userProfile?.id;
        final userEmail = authProvider.userProfile?.email;

        final personality =
            personalityProvider.getPersonalityById(agent.personalityId);
        final personalityPrompt = personality?.behaviorPrompt ?? '';

        await voiceProvider.endSession();
        await Future.delayed(const Duration(milliseconds: 500));

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
          voiceMode: agent.voiceMode,
        );
      }
    } finally {
      _isStartingSession = false;
    }
  }

  Future<void> _handleTap() async {
    final now = DateTime.now();
    final voiceProvider = context.read<VoiceProvider>();

    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _tapCount++;
      if (_tapCount >= 2) {
        _tapCount = 0;
        _lastTapTime = null;

        if (voiceProvider.state == VoiceState.sleep ||
            voiceProvider.state == VoiceState.paused) {
          debugPrint(
              'Double tap detected in ${voiceProvider.state} - waking up/resuming');
          await voiceProvider.resume();
          return;
        }

        _togglePause();
        return;
      }
    } else {
      _tapCount = 1;
    }

    _lastTapTime = now;
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
    await context.read<VoiceProvider>().pause();
  }

  Future<void> _handlePlay() async {
    _hideControlBar();

    final voiceProvider = context.read<VoiceProvider>();

    if (!_sessionStarted) {
      _sessionStarted = true;
      await _startSession();
      return;
    }

    if (voiceProvider.state == VoiceState.sleep) {
      debugPrint('Play button pressed in sleep mode - waking up');
      await voiceProvider.resume();
    } else {
      await voiceProvider.resume();
    }
  }

  Future<void> _handleRefresh() async {
    final agentProvider = context.read<AgentProvider>();
    final voiceProvider = context.read<VoiceProvider>();
    final agent = agentProvider.activeAgent;

    if (agent != null) {
      await voiceProvider.refreshSession(agent.id);
      await Future.delayed(const Duration(milliseconds: 500));

      _sessionStarted = true;
      _startSession();
    }
  }

  Future<void> _handleExit() async {
    _hideControlBar();

    WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );

    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.endSession();

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
                    GestureDetector(
                      onTap: _hideControlBar,
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                      ),
                    ),
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
