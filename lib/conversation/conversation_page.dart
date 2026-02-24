import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/providers.dart';
import '../providers/reports_provider.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../services/services.dart';
import '../services/reminder_scheduler_service.dart';
import '../services/report_scheduler_service.dart';
import '../services/note_tools_handler.dart';
import '../game/game_page_content.dart';
import '../face/face_page_content.dart';
import '../chat/chat_page.dart';
import '../notes/notes_page.dart';
import '../notes/note_view_page.dart';
import '../reports/reports_page.dart';
import '../reminders/schedule_page.dart';

/// Main conversation page with swipeable navigation between Chat, Face, and Notes
class ConversationPage extends StatefulWidget {
  final VoidCallback onExit;

  const ConversationPage({
    super.key,
    required this.onExit,
  });

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  late PageController _pageController;
  int _currentPage = 1; // Start on Face page (center)
  bool _isStartingSession = false;
  
  // Keys to access page states for external control
  final GlobalKey<ChatPageState> _chatPageKey = GlobalKey<ChatPageState>();
  final GlobalKey<NotesPageState> _notesPageKey = GlobalKey<NotesPageState>();
  final GlobalKey<ReportsPageState> _reportsPageKey = GlobalKey<ReportsPageState>();
  final GlobalKey<SchedulePageState> _schedulePageKey = GlobalKey<SchedulePageState>();

  // Page indices
  static const int gamePageIndex = 0;
  static const int chatPageIndex = 1;
  static const int facePageIndex = 2;
  static const int reportsPageIndex = 3;
  static const int notesPageIndex = 4;
  static const int schedulePageIndex = 5;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: facePageIndex);
    
    // Enable wakelock
    WakelockPlus.enable();
    
    // Start with face page - hide status bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // Notify scheduler that we're on the face page
    ReminderSchedulerService.getInstance().setOnFacePage(true);

    // Start report scheduler (only runs when in conversation)
    final reportScheduler = ReportSchedulerService.getInstance();
    reportScheduler.setInConversation(true);
    reportScheduler.setVoiceProvider(context.read<VoiceProvider>());
    reportScheduler.setReportsProvider(context.read<ReportsProvider>());
    reportScheduler.start();

    // Set up AI navigation callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAINavigation();
      _startSession();
    });
  }
  
  /// Update status bar visibility based on current page
  void _updateStatusBar(int pageIndex) {
    if (pageIndex == facePageIndex) {
      // Face page - hide status bar for immersive experience
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // Other pages (Game, Chat, Notes, Schedule) - show status bar with white icons
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top],
      );
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // White icons for dark background
        statusBarBrightness: Brightness.dark, // iOS: white text
      ));
    }
  }
  
  /// Set up AI navigation callbacks for voice-controlled navigation
  void _setupAINavigation() {
    final voiceProvider = context.read<VoiceProvider>();
    
    voiceProvider.noteToolsHandler.onNavigate = (target, {Note? note}) {
      debugPrint('AI Navigation requested: $target, note: ${note?.title}');
      
      // First, pop any pushed routes (like NoteViewPage) before navigating
      // This ensures we can navigate in the PageView
      _popToBaseAndThen(() {
        switch (target) {
          case AINavigationTarget.notesList:
            _navigateToPage(notesPageIndex);
            break;
            
          case AINavigationTarget.noteView:
            if (note != null) {
              _openNoteViewFromAI(note);
            }
            break;
            
          case AINavigationTarget.face:
            _navigateToPage(facePageIndex);
            break;
            
          case AINavigationTarget.chat:
            _navigateToPage(chatPageIndex);
            break;
            
          case AINavigationTarget.imageGenerator:
            _navigateToPageWithImageMode();
            break;
            
          case AINavigationTarget.schedule:
            _navigateToPage(schedulePageIndex);
            break;

          case AINavigationTarget.game:
            _jumpToPage(gamePageIndex);
            break;

          case AINavigationTarget.reports:
            _navigateToPage(reportsPageIndex);
            break;

          case AINavigationTarget.reportView:
            // Report view navigation is handled via _openReportViewFromAI
            break;
        }
      });
    };
    
    // Set up callback for when notes list should refresh
    voiceProvider.noteToolsHandler.onNotesListChanged = () {
      debugPrint('AI triggered notes list refresh');
      _notesPageKey.currentState?.refreshNotes();
    };
    
    // Set up callback for when schedule list should refresh
    voiceProvider.noteToolsHandler.onScheduleListChanged = () {
      debugPrint('AI triggered schedule list refresh');
      _schedulePageKey.currentState?.refreshSchedule();
    };

    // Set up callback for when reports list should refresh
    voiceProvider.noteToolsHandler.onReportsListChanged = () {
      debugPrint('AI triggered reports list refresh');
      _reportsPageKey.currentState?.refreshReports();
    };

    // Set up callback for triggering report check-in after navigation
    voiceProvider.noteToolsHandler.onTriggerReportCheckIn = ({bool skipIntro = false}) {
      debugPrint('AI triggered report check-in (skipIntro: $skipIntro)');
      voiceProvider.triggerReportCheckIn(skipIntro: skipIntro);
    };

    // Set up callback for report filter changes (from tool)
    voiceProvider.noteToolsHandler.onSetReportFilter = (filter) {
      debugPrint('Tool triggered report filter change: $filter');
      final filterEnum = switch (filter.toLowerCase()) {
        'live' => ReportFilter.live,
        'history' => ReportFilter.history,
        'saved' => ReportFilter.saved,
        _ => ReportFilter.live,
      };
      _reportsPageKey.currentState?.setFilter(filterEnum);
    };

    // Set up callback for report category changes (from tool)
    voiceProvider.noteToolsHandler.onSetReportCategory = (category) {
      debugPrint('Tool triggered report category change: $category');
      _reportsPageKey.currentState?.setCategory(category);
    };

    // Set up callback for game navigation
    voiceProvider.onNavigateToGame = () {
      debugPrint('Game navigation requested');
      _jumpToPage(gamePageIndex);
    };

    // Set up fallback callback for reports navigation (from AI marker detection)
    voiceProvider.onNavigateToReports = () {
      debugPrint('Reports navigation requested by AI (marker fallback)');
      _jumpToPage(reportsPageIndex);
    };

    // Set up callback for scheduled report check-in (navigate + start playing)
    voiceProvider.onNavigateToReportsAndPlay = () {
      debugPrint('Reports navigation + playback requested (scheduled check-in)');
      _jumpToPage(reportsPageIndex);
      // Delay slightly to let the page render, then start playback
      Future.delayed(const Duration(milliseconds: 300), () {
        _reportsPageKey.currentState?.startPlayback();
      });
    };

    // Note: Game/lesson mode callbacks (onStartLessonMode, onExitLessonMode) are
    // wired internally in VoiceProvider._setupGameController()

    // Note: Pause is handled via flag in noteToolsHandler.checkAndClearPauseFlag()
    // The pipeline checks this flag after playing the response and pauses then
  }
  
  /// Open a note view page triggered by AI
  void _openNoteViewFromAI(Note note) {
    // Show status bar with white icons for the pushed page
    _updateStatusBar(notesPageIndex); // Use non-face page to show status bar
    
    // Push the note view on top of current page
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => NoteViewPage(
          note: note,
          onNoteUpdated: (updatedNote) {
            // Update active note in handler
            final voiceProvider = context.read<VoiceProvider>();
            voiceProvider.noteToolsHandler.setActiveNote(updatedNote);
          },
          onNoteDeleted: () {
            final voiceProvider = context.read<VoiceProvider>();
            voiceProvider.noteToolsHandler.setActiveNote(null);
          },
          onPause: () => context.read<VoiceProvider>().pause(),
          onPlay: () => context.read<VoiceProvider>().resume(),
          onRefresh: _handleRefreshFromChat,
          onExit: _handleExit,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    
    // Notify scheduler that we're leaving
    ReminderSchedulerService.getInstance().setOnFacePage(false);

    // Stop report scheduler (user leaving conversation)
    ReportSchedulerService.getInstance().stop();

    // Disable wakelock
    WakelockPlus.disable();
    
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    
    super.dispose();
  }

  Future<void> _startSession() async {
    if (_isStartingSession) return;
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
        final userId = authProvider.userProfile?.id;
        final userEmail = authProvider.userProfile?.email;
        final dreamCloudService = aiServiceProvider.dreamCloudService;
        final subscriptionStatus = dreamCloudService?.status;
        final personality = personalityProvider.getPersonalityById(agent.personalityId);
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
          subscriptionStatus: subscriptionStatus,
        );
      }
    } finally {
      _isStartingSession = false;
    }
  }

  void _navigateToPage(int pageIndex) {
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Instant navigation (no animation) - used for AI-triggered navigation
  void _jumpToPage(int pageIndex) {
    debugPrint('ConversationPage._jumpToPage: jumping to page $pageIndex, current=${_pageController.page}');
    if (!mounted) {
      debugPrint('ConversationPage._jumpToPage: NOT MOUNTED, skipping');
      return;
    }
    _pageController.jumpToPage(pageIndex);
    setState(() {
      _currentPage = pageIndex;
    });
    // Update status bar for new page
    _updateStatusBar(pageIndex);
    debugPrint('ConversationPage._jumpToPage: done, _currentPage=$_currentPage');
  }

  void _navigateToGame() => _navigateToPage(gamePageIndex);
  void _navigateToChat() => _navigateToPage(chatPageIndex);
  void _navigateToFace() => _navigateToPage(facePageIndex);
  void _navigateToReports() => _navigateToPage(reportsPageIndex);
  void _navigateToNotes() => _navigateToPage(notesPageIndex);
  void _navigateToSchedule() => _navigateToPage(schedulePageIndex);
  
  /// Pop any pushed routes (like NoteViewPage) and then execute callback
  void _popToBaseAndThen(VoidCallback onComplete) {
    if (Navigator.canPop(context)) {
      debugPrint('ConversationPage: Popping pushed route before navigation');
      Navigator.pop(context);
      // Small delay to let the pop complete
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // Restore status bar state based on current page
          _updateStatusBar(_currentPage);
          onComplete();
        }
      });
    } else {
      onComplete();
    }
  }
  
  void _navigateToPageWithImageMode() {
    debugPrint('ConversationPage: Navigating to image mode');
    _navigateToPage(chatPageIndex);
    // Switch to image mode after navigation - need slight delay for page to be ready
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        final state = _chatPageKey.currentState;
        debugPrint('ConversationPage: ChatPage state available: ${state != null}');
        state?.switchToImageMode();
      }
    });
  }
  
  Future<void> _handleRefreshFromChat() async {
    final voiceProvider = context.read<VoiceProvider>();
    final agentProvider = context.read<AgentProvider>();
    final agent = agentProvider.activeAgent;
    
    if (agent != null) {
      // Clear conversation and restart session
      await voiceProvider.refreshSession(agent.id);
      await Future.delayed(const Duration(milliseconds: 300));
      await _startSession();
    }
  }

  Future<void> _handleExit() async {
    WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );

    // Notify scheduler we're leaving the face page
    ReminderSchedulerService.getInstance().setOnFacePage(false);

    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.endLessonMode(); // Reset game state
    await voiceProvider.endSession();
    await Future.delayed(const Duration(milliseconds: 300));

    widget.onExit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
          
          // Update status bar visibility based on page
          _updateStatusBar(index);
          
          final voiceProvider = context.read<VoiceProvider>();

          // Pause for chat page (text/image input) and game page (manual selection until game starts)
          if (index == chatPageIndex || index == gamePageIndex) {
            // Only pause if session is actively running (not during initialization)
            // Check for active session states: listening, speaking, thinking, processing
            if (voiceProvider.state.isSessionActive &&
                voiceProvider.state != VoiceState.paused) {
              voiceProvider.pause();
            }
          }
          // Note: Don't auto-resume when returning to face page
          // User must explicitly press play or double-tap to resume
        },
        children: [
          // Page 0: Game Page
          GamePageContent(
            onNavigateToFace: _navigateToFace,
            onPause: () => context.read<VoiceProvider>().pause(),
            onPlay: () => context.read<VoiceProvider>().resume(),
            onRefresh: _handleRefreshFromChat,
            onExit: _handleExit,
            onSkip: () => context.read<VoiceProvider>().gameController.skipQuestion(),
            onStart: () {
              // Apply game settings before starting
              final voiceProvider = context.read<VoiceProvider>();
              final gameSettingsProvider = context.read<GameSettingsProvider>();
              voiceProvider.setGameSettings(gameSettingsProvider.settings);
              voiceProvider.startGame();
            },
            onGamePause: () => context.read<VoiceProvider>().pauseGame(),
            onGameResume: () => context.read<VoiceProvider>().resumeGame(),
            onRecord: () => context.read<VoiceProvider>().startGameRecording(),
          ),

          // Page 1: Chat/Image Page
          ChatPage(
            key: _chatPageKey,
            onNavigateToFace: _navigateToFace,
            onRefresh: _handleRefreshFromChat,
          ),

          // Page 2: Face Page (center, default)
          FacePageContent(
            onExit: _handleExit,
            onNavigateToGame: _navigateToGame,
            onNavigateToChat: _navigateToChat,
            onNavigateToReports: _navigateToReports,
            onNavigateToNotes: _navigateToNotes,
            onNavigateToSchedule: _navigateToSchedule,
            onRefreshSession: _startSession,
          ),

          // Page 3: Reports Page
          ReportsPage(
            key: _reportsPageKey,
            onNavigateToFace: _navigateToFace,
            onPause: () => context.read<VoiceProvider>().pause(),
            onPlay: () => context.read<VoiceProvider>().resume(),
            onRefresh: _handleRefreshFromChat,
            onExit: _handleExit,
          ),

          // Page 4: Notes Page
          NotesPage(
            key: _notesPageKey,
            onNavigateToFace: _navigateToFace,
            onPause: () => context.read<VoiceProvider>().pause(),
            onPlay: () => context.read<VoiceProvider>().resume(),
            onRefresh: _handleRefreshFromChat,
            onExit: _handleExit,
          ),

          // Page 5: Schedule Page
          SchedulePage(
            key: _schedulePageKey,
            onNavigateToFace: _navigateToFace,
            onPause: () => context.read<VoiceProvider>().pause(),
            onPlay: () => context.read<VoiceProvider>().resume(),
            onRefresh: _handleRefreshFromChat,
            onExit: _handleExit,
          ),
        ],
      ),
    );
  }
}
