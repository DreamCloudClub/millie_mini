import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/services.dart';
import 'services/image_cache_service.dart';
import 'providers/providers.dart';
import 'providers/openclaw_provider.dart';
import 'providers/reports_provider.dart';
import 'utils/constants.dart';
import 'splash_page.dart';
import 'auth/login_page.dart';
import 'auth/signup_page.dart';
import 'dashboard/dashboard_page.dart';
import 'dashboard/user_profile_edit_page.dart';
import 'dashboard/account_settings_edit_page.dart';
import 'dashboard/game_settings_edit_page.dart';
import 'dashboard/brain_settings_page.dart';
import 'agents/agent_profiles_page.dart';
import 'agents/edit_agent_page.dart';
import 'personalities/personality_builder_page.dart';
import 'ai_services/ai_services_page.dart';
import 'ai_services/edit_dream_cloud_page.dart';
import 'ai_services/edit_custom_service_page.dart';
import 'conversation/conversation_page.dart';
import 'reminders/edit_alert_page.dart';
import 'dashboard/edit_custom_quiz_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Default: Show status bar, hide navigation bar
  // This gives a clean look while keeping time/battery visible
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  
  // Lock orientation to portrait for phones, allow all for tablets
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Initialize Supabase
  await SupabaseConfig.initialize();
  
  // Initialize storage service
  final storageService = StorageService();
  await storageService.init();
  
  runApp(MillieMiniApp(storageService: storageService));
}

class MillieMiniApp extends StatelessWidget {
  final StorageService storageService;
  
  const MillieMiniApp({
    super.key,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => AgentProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => PersonalityProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => AIServiceProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => VoiceProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => ReminderProvider(
            openaiService: OpenAIService(storageService),
            storageService: storageService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => GameSettingsProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => CustomQuizProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => FaceImageProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => OpenClawProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => ReportsProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Millie Mini',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: AppTextStyles.fontFamily,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.dreamCloudBlue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
          ),
        ),
        home: const AppNavigator(),
      ),
    );
  }
}

class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  bool _isInitialized = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize AuthProvider first (needed for other providers)
    await context.read<AuthProvider>().init();
    
    // Initialize notification service (needed for reminder alerts)
    final notificationService = ReminderNotificationService.getInstance();
    await notificationService.initialize();
    
    // Then initialize others (some depend on auth state)
    await Future.wait([
      context.read<AgentProvider>().init(),
      context.read<PersonalityProvider>().init(),
      context.read<AIServiceProvider>().init(),
      context.read<ReminderProvider>().init(),
      context.read<GameSettingsProvider>().init(),
      context.read<CustomQuizProvider>().loadQuizzes(),
      context.read<FaceImageProvider>().init(),
      context.read<OpenClawProvider>().init(),
      context.read<ReportsProvider>().init(),
    ]);
    
    // Wire up ReminderIntentHandler in VoiceProvider
    final voiceProvider = context.read<VoiceProvider>();
    final reminderProvider = context.read<ReminderProvider>();
    voiceProvider.setReminderProvider(reminderProvider);

    // Wire up CustomQuizProvider for custom game quizzes
    final customQuizProvider = context.read<CustomQuizProvider>();
    voiceProvider.setCustomQuizProvider(customQuizProvider);

    // Wire up OpenClawProvider for alternative LLM routing
    final openClawProvider = context.read<OpenClawProvider>();
    voiceProvider.setOpenClawProvider(openClawProvider);

    // Wire up ReportsProvider for AI reports
    final reportsProvider = context.read<ReportsProvider>();
    voiceProvider.setReportsProvider(reportsProvider);

    // Initialize WeatherService if API key is configured in Supabase
    try {
      debugPrint('Fetching OpenWeather API key from Supabase...');
      final weatherResponse = await SupabaseConfig.client
          .from('service_config')
          .select('api_key')
          .eq('service_name', 'openweather')
          .eq('is_active', true)
          .maybeSingle();

      debugPrint('Weather response: $weatherResponse');
      if (weatherResponse != null && weatherResponse['api_key'] != null) {
        final weatherApiKey = weatherResponse['api_key'] as String;
        if (weatherApiKey.isNotEmpty) {
          voiceProvider.setWeatherApiKey(weatherApiKey);
          debugPrint('Weather service initialized with key');
        } else {
          debugPrint('Weather API key is empty');
        }
      } else {
        debugPrint('No OpenWeather config found in Supabase');
      }
    } catch (e) {
      debugPrint('Error fetching OpenWeather API key: $e');
    }

    // Initialize reminder scheduler (only if user is logged in)
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isLoggedIn) {
      final scheduler = ReminderSchedulerService.getInstance();

      // Set VoiceProvider reference for face mode alerts
      scheduler.setVoiceProvider(voiceProvider);
      // Set ReminderProvider reference for refreshing lists after alerts trigger
      scheduler.setReminderProvider(reminderProvider);

      // Start scheduler
      scheduler.start();

      debugPrint('Reminder scheduler started');

      // Sync animal and face images in background (don't await - non-blocking)
      ImageCacheService.syncAnimalImages();
      ImageCacheService.syncFaceImages();
    }
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _onSplashComplete() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashPage(
        onInitComplete: _onSplashComplete,
      );
    }

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!_isInitialized || auth.isLoading) {
          return const Scaffold(
            backgroundColor: AppColors.dreamCloudBlue,
            body: Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          );
        }

        if (!auth.isLoggedIn) {
          return const AuthNavigator();
        }

        return const MainNavigator();
      },
    );
  }
}

/// Handles auth flow navigation
class AuthNavigator extends StatefulWidget {
  const AuthNavigator({super.key});

  @override
  State<AuthNavigator> createState() => _AuthNavigatorState();
}

class _AuthNavigatorState extends State<AuthNavigator> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return LoginPage(
        onSignUpTap: () => setState(() => _showLogin = false),
        onLoginSuccess: () {}, // Auth state change will trigger rebuild
      );
    }

    return SignUpPage(
      onLoginTap: () => setState(() => _showLogin = true),
      onSignUpSuccess: () {}, // Auth state change will trigger rebuild
    );
  }
}

/// Handles main app navigation after login
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

enum MainRoute {
  dashboard,
  face,
  userProfile,
  accountSettings,
  gameSettings,
  brainSettings,
  agentProfiles,
  editAgent,
  personalityBuilder,
  aiServices,
  dreamCloud,
  customService,
  editAlert,
  createAlert,
  editCustomQuiz,
}

class _MainNavigatorState extends State<MainNavigator> {
  final List<_RouteEntry> _routeStack = [_RouteEntry(MainRoute.dashboard)];

  void _push(MainRoute route, {Map<String, dynamic>? params}) {
    setState(() {
      _routeStack.add(_RouteEntry(route, params: params));
    });
  }

  void _pop() {
    if (_routeStack.length > 1) {
      setState(() {
        _routeStack.removeLast();
      });
    }
  }

  void _popToRoot() {
    setState(() {
      _routeStack.removeRange(1, _routeStack.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = _routeStack.last;

    switch (currentRoute.route) {
      case MainRoute.dashboard:
        return DashboardPage(
          onLaunchMillie: () => _push(MainRoute.face),
          onEditAgentProfile: () => _push(MainRoute.agentProfiles),
          onEditUserProfile: () => _push(MainRoute.userProfile),
          onEditAIService: () => _push(MainRoute.aiServices),
          onEditAccountSettings: () => _push(MainRoute.accountSettings),
          onEditGameSettings: () => _push(MainRoute.gameSettings),
          onEditBrain: () => _push(MainRoute.brainSettings),
        );

      case MainRoute.face:
        return ConversationPage(
          onExit: _popToRoot,
        );

      case MainRoute.userProfile:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: UserProfileEditPage(
            onSaved: _pop,
          ),
        );

      case MainRoute.accountSettings:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: AccountSettingsEditPage(
            onBack: _pop,
            onLogout: () {}, // Auth state change will handle navigation
            onDeleteAccount: () {}, // Auth state change will handle navigation
          ),
        );

      case MainRoute.gameSettings:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: GameSettingsEditPage(
            onSaved: _pop,
            onEditCustomQuiz: (quizId) => _push(
              MainRoute.editCustomQuiz,
              params: {'quizId': quizId},
            ),
          ),
        );

      case MainRoute.brainSettings:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: BrainSettingsPage(
            onBack: _pop,
          ),
        );

      case MainRoute.agentProfiles:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: AgentProfilesPage(
            onBack: _pop,
            onEditAgent: (agentId) => _push(
              MainRoute.editAgent,
              params: {'agentId': agentId},
            ),
          ),
        );

      case MainRoute.editAgent:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: EditAgentPage(
            agentId: currentRoute.params?['agentId'] as String?,
            onBack: _pop,
            onSaved: _pop,
            onEditPersonality: (personalityId, isCustomize) => _push(
              MainRoute.personalityBuilder,
              params: {
                'personalityId': personalityId,
                'isCustomize': isCustomize,
              },
            ),
          ),
        );

      case MainRoute.personalityBuilder:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: PersonalityBuilderPage(
            personalityId: currentRoute.params?['personalityId'] as String?,
            isCustomize: currentRoute.params?['isCustomize'] as bool? ?? false,
            onBack: _pop,
            onSaved: _pop,
          ),
        );

      case MainRoute.aiServices:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: AIServicesPage(
            onBack: _pop,
            onEditDreamCloud: () => _push(MainRoute.dreamCloud),
            onEditCustomService: (serviceId) => _push(
              MainRoute.customService,
              params: {'serviceId': serviceId},
            ),
          ),
        );

      case MainRoute.dreamCloud:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: EditDreamCloudPage(
            onBack: _pop,
          ),
        );

      case MainRoute.customService:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: EditCustomServicePage(
            serviceId: currentRoute.params?['serviceId'] as String?,
            onBack: _pop,
            onSaved: _pop,
          ),
        );

      case MainRoute.editAlert:
      case MainRoute.createAlert:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: EditAlertPage(
            reminderId: currentRoute.params?['reminderId'] as String?,
            onBack: _pop,
            onSaved: _pop,
          ),
        );

      case MainRoute.editCustomQuiz:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: EditCustomQuizPage(
            quizId: currentRoute.params?['quizId'] as String?,
            onBack: _pop,
            onSaved: _pop,
          ),
        );
    }
  }
}

class _RouteEntry {
  final MainRoute route;
  final Map<String, dynamic>? params;

  _RouteEntry(this.route, {this.params});
}
