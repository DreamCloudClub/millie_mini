import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/services.dart';
import 'providers/providers.dart';
import 'providers/openclaw_provider.dart';
import 'utils/constants.dart';
import 'dashboard/dashboard_page.dart';
import 'dashboard/user_profile_edit_page.dart';
import 'dashboard/brain_settings_page.dart';
import 'dashboard/device_settings_page.dart';
import 'agents/agent_profiles_page.dart';
import 'agents/edit_agent_page.dart';
import 'personalities/personality_builder_page.dart';
import 'ai_services/ai_services_page.dart';
import 'conversation/conversation_page.dart';
import 'reminders/edit_alert_page.dart';
import 'conversations/conversations_page.dart';
import 'conversations/conversation_templates_page.dart';
import 'conversations/edit_conversation_page.dart';
import 'conversations/conversation_kiosk_page.dart';
import 'conversations/reports_page.dart';
import 'conversations/view_report_page.dart';
import 'inventory/inventory_page.dart';

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
          create: (_) => CustomFaceProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => OpenClawProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => ConversationTemplateProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => ConversationReportProvider(storageService),
        ),
        ChangeNotifierProvider(
          create: (_) => InventoryProvider(storageService),
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

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize AuthProvider first (creates local user)
    await context.read<AuthProvider>().init();

    // Initialize notification service (needed for reminder alerts)
    final notificationService = ReminderNotificationService.getInstance();
    await notificationService.initialize();

    // Then initialize others
    await Future.wait([
      context.read<AgentProvider>().init(),
      context.read<PersonalityProvider>().init(),
      context.read<AIServiceProvider>().init(),
      context.read<ReminderProvider>().init(),
      context.read<CustomFaceProvider>().init(),
      context.read<OpenClawProvider>().init(),
      context.read<ConversationTemplateProvider>().init(),
      context.read<ConversationReportProvider>().init(),
      context.read<InventoryProvider>().init(),
    ]);

    // Wire up ReminderIntentHandler in VoiceProvider
    final voiceProvider = context.read<VoiceProvider>();
    final reminderProvider = context.read<ReminderProvider>();
    voiceProvider.setReminderProvider(reminderProvider);

    // Let the AI answer "where is X" from store inventory
    voiceProvider.setInventoryProvider(context.read<InventoryProvider>());

    // Wire up OpenClawProvider for alternative LLM routing
    final openClawProvider = context.read<OpenClawProvider>();
    voiceProvider.setOpenClawProvider(openClawProvider);

    // Set OpenAI API key for realtime voice service
    final aiServiceProvider = context.read<AIServiceProvider>();
    final openAiKey = aiServiceProvider.openaiApiKey;
    if (openAiKey != null && openAiKey.isNotEmpty) {
      voiceProvider.setOpenAIApiKey(openAiKey);
    }

    // Initialize reminder scheduler
    final scheduler = ReminderSchedulerService.getInstance();

    // Set VoiceProvider reference for face mode alerts
    scheduler.setVoiceProvider(voiceProvider);
    // Set ReminderProvider reference for refreshing lists after alerts trigger
    scheduler.setReminderProvider(reminderProvider);

    // Start scheduler
    scheduler.start();

    debugPrint('Reminder scheduler started');

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: AppColors.dreamCloudBlue,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    // Go directly to main navigator (no auth required)
    return const MainNavigator();
  }
}

/// Handles main app navigation
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

enum MainRoute {
  dashboard,
  face,
  userProfile,
  brainSettings,
  deviceSettings,
  agentProfiles,
  editAgent,
  personalityBuilder,
  aiServices,
  editAlert,
  createAlert,
  conversations,
  conversationTemplates,
  editConversation,
  conversationKiosk,
  reports,
  viewReport,
  inventory,
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
          onLaunchKiosk: (templateId) => _push(
            MainRoute.conversationKiosk,
            params: {'templateId': templateId},
          ),
          onEditAgentProfile: () => _push(MainRoute.agentProfiles),
          onEditUserProfile: () => _push(MainRoute.userProfile),
          onEditAIService: () => _push(MainRoute.aiServices),
          onEditBrain: () => _push(MainRoute.brainSettings),
          onEditDeviceSettings: () => _push(MainRoute.deviceSettings),
          onEditConversations: () => _push(MainRoute.conversations),
          onViewReports: () => _push(MainRoute.reports),
          onEditInventory: () => _push(MainRoute.inventory),
        );

      case MainRoute.inventory:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: InventoryPage(onBack: _pop),
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

      case MainRoute.deviceSettings:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: DeviceSettingsPage(
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

      case MainRoute.conversations:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: ConversationsPage(
            onBack: _pop,
            onBrowseTemplates: () => _push(MainRoute.conversationTemplates),
            onEditConversation: (conversationId) => _push(
              MainRoute.editConversation,
              params: {'conversationId': conversationId},
            ),
          ),
        );

      case MainRoute.conversationTemplates:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: ConversationTemplatesPage(
            onBack: _pop,
            onSelectTemplate: (template) => _push(
              MainRoute.editConversation,
              params: {'starterTemplate': template},
            ),
          ),
        );

      case MainRoute.editConversation:
        final isFromTemplate = currentRoute.params?['starterTemplate'] != null;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: EditConversationPage(
            conversationId: currentRoute.params?['conversationId'] as String?,
            starterTemplate: currentRoute.params?['starterTemplate'] as StarterTemplate?,
            onBack: _pop,
            onSaved: isFromTemplate
                ? () { _pop(); _pop(); } // Skip templates page, go to Conversations
                : _pop,
          ),
        );

      case MainRoute.conversationKiosk:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _popToRoot();
          },
          child: ConversationKioskPage(
            templateId: currentRoute.params?['templateId'] as String,
            onExit: _popToRoot,
          ),
        );

      case MainRoute.reports:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: ReportsPage(
            onBack: _pop,
            onViewReport: (reportId) => _push(
              MainRoute.viewReport,
              params: {'reportId': reportId},
            ),
          ),
        );

      case MainRoute.viewReport:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _pop();
          },
          child: ViewReportPage(
            reportId: currentRoute.params?['reportId'] as String,
            onBack: _pop,
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
