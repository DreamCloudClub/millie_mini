import 'package:flutter/foundation.dart';

/// Intent categories for routing tool selection
enum IntentCategory {
  apps,       // External apps (YouTube, Spotify, etc.)
  notes,      // Our notes system
  schedule,   // Alerts and reminders
  weather,    // Weather queries
  navigation, // App navigation (go back, show chat, etc.)
  games,      // Games and lessons
  reports,    // AI reports and news
  inventory,  // Store products: locations, prices, stock
  none,       // No tools needed - just conversation
}

/// Routes user messages to appropriate tool categories
/// This saves tokens by only sending relevant tools to the LLM
class IntentRouter {

  /// Known external app names (to distinguish from our app features)
  static const Set<String> _externalAppNames = {
    // Video
    'youtube', 'yt', 'netflix', 'hulu', 'disney', 'prime video', 'twitch',
    // Music
    'spotify', 'apple music', 'pandora', 'soundcloud',
    // Maps
    'google maps', 'maps', 'waze',
    // Social
    'instagram', 'insta', 'facebook', 'twitter', 'x', 'tiktok', 'reddit',
    'snapchat', 'linkedin', 'pinterest',
    // Communication
    'whatsapp', 'telegram', 'discord', 'zoom', 'slack', 'messenger',
    // Google
    'gmail', 'google drive', 'google calendar', 'google docs', 'google sheets',
    // Shopping
    'amazon', 'ebay', 'walmart', 'target',
    // Food
    'uber eats', 'doordash', 'grubhub',
    // Ride sharing
    'uber', 'lyft',
    // Finance
    'venmo', 'paypal', 'cash app',
    // System
    'camera', 'settings', 'calculator',
    // Other
    'imdb', 'yelp', 'wikipedia',
  };

  /// Keywords that indicate app launching intent
  static const List<String> _appLaunchPrefixes = [
    'open ',
    'launch ',
    'start ',
    'go to ',
    'pull up ',
    'bring up ',
  ];

  /// Keywords for "play X on Y" pattern (e.g., "play Taylor Swift on Spotify")
  static const List<String> _playOnPatterns = [
    ' on spotify',
    ' on youtube',
    ' on netflix',
    ' on apple music',
    ' on pandora',
    ' on amazon',
  ];

  /// Detect intent categories from user message
  /// Returns a set of categories (can be multiple for ambiguous requests)
  static Set<IntentCategory> detectIntent(String message) {
    final lower = message.toLowerCase().trim();
    final categories = <IntentCategory>{};

    // Check for external app intent first (most specific)
    if (_isExternalAppIntent(lower)) {
      categories.add(IntentCategory.apps);
      debugPrint('IntentRouter: Detected apps intent');
    }

    // Check for weather intent
    if (_isWeatherIntent(lower)) {
      categories.add(IntentCategory.weather);
      debugPrint('IntentRouter: Detected weather intent');
    }

    // Check for schedule/alert intent
    if (_isScheduleIntent(lower)) {
      categories.add(IntentCategory.schedule);
      debugPrint('IntentRouter: Detected schedule intent');
    }

    // Check for notes intent (our app's notes, not "notes app")
    if (_isNotesIntent(lower)) {
      categories.add(IntentCategory.notes);
      debugPrint('IntentRouter: Detected notes intent');
    }

    // Check for games intent
    if (_isGamesIntent(lower)) {
      categories.add(IntentCategory.games);
      debugPrint('IntentRouter: Detected games intent');
    }

    // Check for navigation intent
    if (_isNavigationIntent(lower)) {
      categories.add(IntentCategory.navigation);
      debugPrint('IntentRouter: Detected navigation intent');
    }

    // Check for reports intent
    if (_isReportsIntent(lower)) {
      categories.add(IntentCategory.reports);
      debugPrint('IntentRouter: Detected reports intent');
    }

    // Check for store inventory intent
    if (_isInventoryIntent(lower)) {
      categories.add(IntentCategory.inventory);
      debugPrint('IntentRouter: Detected inventory intent');
    }

    // If no specific intent detected, it's just conversation
    if (categories.isEmpty) {
      categories.add(IntentCategory.none);
      debugPrint('IntentRouter: No specific intent - conversation only');
    }

    return categories;
  }

  /// Check if message is about external apps
  static bool _isExternalAppIntent(String lower) {
    // Check for "open/launch X" patterns
    for (final prefix in _appLaunchPrefixes) {
      if (lower.startsWith(prefix)) {
        final remainder = lower.substring(prefix.length);

        // "open notes" or "open my notes" → NOT external (it's our notes)
        if (remainder.startsWith('note') ||
            remainder.startsWith('my note') ||
            remainder.startsWith('the note')) {
          continue; // Skip, this is our notes feature
        }

        // "open notes app" or "open the notes app" → external
        if (remainder.contains('app')) {
          return true;
        }

        // Check if it's a known external app
        for (final app in _externalAppNames) {
          if (remainder.startsWith(app) || remainder.contains(app)) {
            return true;
          }
        }

        // "open camera", "open settings" etc.
        if (remainder.startsWith('camera') ||
            remainder.startsWith('settings') ||
            remainder.startsWith('calculator')) {
          return true;
        }
      }
    }

    // Check for "play X on Y" pattern
    for (final pattern in _playOnPatterns) {
      if (lower.contains(pattern)) {
        return true;
      }
    }

    // Check for "search for X on Y" pattern
    if (lower.contains(' on google maps') ||
        lower.contains(' on amazon') ||
        lower.contains(' on youtube') ||
        lower.contains(' on reddit') ||
        lower.contains(' on ebay')) {
      return true;
    }

    return false;
  }

  /// Check if message is about weather
  static bool _isWeatherIntent(String lower) {
    return lower.contains('weather') ||
           lower.contains('temperature') ||
           lower.contains('forecast') ||
           lower.contains('rain') ||
           lower.contains('sunny') ||
           lower.contains('cloudy') ||
           lower.contains('snow') ||
           lower.contains('humid') ||
           lower.contains('air quality') ||
           lower.contains('pollution') ||
           lower.contains('how hot') ||
           lower.contains('how cold') ||
           lower.contains('degrees outside');
  }

  /// Check if message is about schedule/alerts
  static bool _isScheduleIntent(String lower) {
    return lower.contains('remind') ||
           lower.contains('alert') ||
           lower.contains('schedule') ||
           lower.contains('alarm') ||
           lower.contains('appointment') ||
           lower.contains('meeting') ||
           lower.contains('set a timer') ||
           lower.contains('wake me') ||
           lower.contains('notify me') ||
           (lower.contains('at ') && _hasTimePattern(lower)) ||
           (lower.contains('tomorrow') && lower.contains(' at '));
  }

  /// Check for time patterns like "3pm", "3:00", "noon"
  static bool _hasTimePattern(String lower) {
    // Simple time patterns
    return RegExp(r'\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)', caseSensitive: false).hasMatch(lower) ||
           lower.contains('noon') ||
           lower.contains('midnight') ||
           lower.contains('morning') ||
           lower.contains('evening') ||
           lower.contains('tonight');
  }

  /// Check if message is about our notes feature
  static bool _isNotesIntent(String lower) {
    // Exclude "notes app" which is external
    if (lower.contains('notes app') || lower.contains('note app')) {
      return false;
    }

    return lower.contains('note') ||
           lower.contains('shopping list') ||
           lower.contains('to-do') ||
           lower.contains('todo') ||
           lower.contains('write down') ||
           lower.contains('write this down') ||
           lower.contains('save this') ||
           lower.contains('remember this') ||
           lower.contains('jot down') ||
           lower.contains('make a list') ||
           lower.contains('add to the list') ||
           lower.contains('add to my list');
  }

  /// Check if message is about games
  static bool _isGamesIntent(String lower) {
    // Be careful: "play X on Spotify" is apps, not games
    if (_playOnPatterns.any((p) => lower.contains(p))) {
      return false;
    }

    return lower.contains('game') ||
           lower.contains('play a') ||
           lower.contains('let\'s play') ||
           lower.contains('riddle') ||
           lower.contains('joke') ||
           lower.contains('trivia') ||
           lower.contains('spelling') ||
           lower.contains('math') ||
           lower.contains('quiz');
  }

  /// Check if message is about navigation
  static bool _isNavigationIntent(String lower) {
    return lower.contains('go back') ||
           lower.contains('pause') ||
           lower.contains('stop listening') ||
           lower.contains('be quiet') ||
           lower.contains('hold on') ||
           lower.contains('wait') ||
           lower.contains('show chat') ||
           lower.contains('type') ||
           lower.contains('text mode') ||
           lower.contains('generate image') ||
           lower.contains('make an image') ||
           lower.contains('create image') ||
           lower.contains('image generator') ||
           lower.contains('show schedule') ||
           lower.contains('show my schedule') ||
           lower.contains('show games');
  }

  /// Check if message is about AI reports
  static bool _isReportsIntent(String lower) {
    return lower.contains('tell me more') ||
           lower.contains('read it') ||
           lower.contains('read that') ||
           lower.contains('what else') ||
           lower.contains('more about that') ||
           lower.contains('report') ||
           lower.contains('show my reports') ||
           lower.contains('save that') ||
           lower.contains('keep that') ||
           lower.contains('news') ||
           lower.contains('research') ||
           // Filter detection
           lower.contains('saved') ||
           lower.contains('history') ||
           lower.contains('live') ||
           // Category detection
           lower.contains('technology') ||
           lower.contains('tech') ||
           lower.contains('business') ||
           lower.contains('sports') ||
           lower.contains('entertainment') ||
           lower.contains('science') ||
           lower.contains('health') ||
           lower.contains('politics');
  }

  /// Check if message is a shopper asking about products in the store.
  ///
  /// Casts a wide net on purpose: a missed detection means Millie can't answer
  /// "where are the deck screws", while a false one only costs a couple of
  /// tool definitions in the request.
  static bool _isInventoryIntent(String lower) {
    return lower.contains('where') ||
           lower.contains('aisle') ||
           lower.contains('shelf') ||
           lower.contains('in stock') ||
           lower.contains('stock') ||
           lower.contains('inventory') ||
           lower.contains('do you have') ||
           lower.contains('do you carry') ||
           lower.contains('do you sell') ||
           lower.contains('looking for') ||
           lower.contains('i need') ||
           lower.contains('find') ||
           lower.contains('how much') ||
           lower.contains('price') ||
           lower.contains('cost') ||
           lower.contains('sku') ||
           lower.contains('product') ||
           lower.contains('buy');
  }

  /// Get tool names for given categories
  static List<String> getToolNamesForCategories(Set<IntentCategory> categories) {
    final tools = <String>{};

    for (final category in categories) {
      switch (category) {
        case IntentCategory.apps:
          tools.add('open_app');
          break;
        case IntentCategory.notes:
          tools.addAll([
            'create_note',
            'update_note',
            'append_to_note',
            'get_active_note',
            'list_notes',
            'show_note',
            'show_notes_list',
            'close_note',
            'delete_note',
          ]);
          break;
        case IntentCategory.schedule:
          tools.addAll([
            'create_alert',
            'update_alert',
            'delete_alert',
            'list_alerts',
            'show_schedule',
          ]);
          break;
        case IntentCategory.weather:
          tools.addAll([
            'get_weather',
            'get_forecast',
            'get_air_quality',
          ]);
          break;
        case IntentCategory.navigation:
          tools.addAll([
            'go_back',
            'pause_conversation',
            'show_chat',
            'show_image_generator',
            'show_schedule',
            'show_games',
          ]);
          break;
        case IntentCategory.games:
          tools.addAll([
            'start_lesson_mode',
            'exit_lesson_mode',
            'show_games',
          ]);
          break;
        case IntentCategory.reports:
          tools.addAll([
            'show_reports',
            'read_report',
            'save_report',
            'set_report_filter',
            'set_report_category',
          ]);
          break;
        case IntentCategory.inventory:
          tools.addAll([
            'search_inventory',
            'get_product_details',
          ]);
          break;
        case IntentCategory.none:
          // No tools needed
          break;
      }
    }

    return tools.toList();
  }
}
