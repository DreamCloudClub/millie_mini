import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Information about how to launch an app
class AppLaunchInfo {
  final String webUrl;
  final String? deepLinkUrl;
  final String? searchWebUrl;
  final String? searchDeepLinkUrl;

  const AppLaunchInfo({
    required this.webUrl,
    this.deepLinkUrl,
    this.searchWebUrl,
    this.searchDeepLinkUrl,
  });
}

/// Result of launching an app
class AppLaunchResult {
  final bool success;
  final String message;
  final String? appName;

  const AppLaunchResult({
    required this.success,
    required this.message,
    this.appName,
  });
}

/// Service for launching apps and websites
class AppLauncherService {
  /// Map of app names to their launch info
  static const Map<String, AppLaunchInfo> _apps = {
    // Video
    'youtube': AppLaunchInfo(
      webUrl: 'https://www.youtube.com',
      deepLinkUrl: 'youtube://',
      searchWebUrl: 'https://www.youtube.com/results?search_query={query}',
      searchDeepLinkUrl: 'youtube://results?search_query={query}',
    ),
    'netflix': AppLaunchInfo(
      webUrl: 'https://www.netflix.com',
      deepLinkUrl: 'nflx://',
      searchWebUrl: 'https://www.netflix.com/search?q={query}',
    ),
    'hulu': AppLaunchInfo(
      webUrl: 'https://www.hulu.com',
      searchWebUrl: 'https://www.hulu.com/search?q={query}',
    ),
    'disney+': AppLaunchInfo(
      webUrl: 'https://www.disneyplus.com',
      deepLinkUrl: 'disneyplus://',
      searchWebUrl: 'https://www.disneyplus.com/search?q={query}',
    ),
    'prime video': AppLaunchInfo(
      webUrl: 'https://www.primevideo.com',
      deepLinkUrl: 'primevideo://',
      searchWebUrl: 'https://www.primevideo.com/search?phrase={query}',
    ),
    'twitch': AppLaunchInfo(
      webUrl: 'https://www.twitch.tv',
      deepLinkUrl: 'twitch://',
      searchWebUrl: 'https://www.twitch.tv/search?term={query}',
    ),

    // Music
    'spotify': AppLaunchInfo(
      webUrl: 'https://open.spotify.com',
      deepLinkUrl: 'spotify://',
      searchWebUrl: 'https://open.spotify.com/search/{query}',
      searchDeepLinkUrl: 'spotify:search:{query}',
    ),
    'apple music': AppLaunchInfo(
      webUrl: 'https://music.apple.com',
      deepLinkUrl: 'music://',
      searchWebUrl: 'https://music.apple.com/search?term={query}',
    ),
    'pandora': AppLaunchInfo(
      webUrl: 'https://www.pandora.com',
      deepLinkUrl: 'pandora://',
      searchWebUrl: 'https://www.pandora.com/search/{query}',
    ),
    'soundcloud': AppLaunchInfo(
      webUrl: 'https://soundcloud.com',
      deepLinkUrl: 'soundcloud://',
      searchWebUrl: 'https://soundcloud.com/search?q={query}',
    ),

    // Maps & Navigation
    'google maps': AppLaunchInfo(
      webUrl: 'https://www.google.com/maps',
      deepLinkUrl: 'comgooglemaps://',
      searchWebUrl: 'https://www.google.com/maps/search/{query}',
      searchDeepLinkUrl: 'comgooglemaps://?q={query}',
    ),
    'waze': AppLaunchInfo(
      webUrl: 'https://www.waze.com/live-map',
      deepLinkUrl: 'waze://',
      searchWebUrl: 'https://www.waze.com/ul?q={query}',
      searchDeepLinkUrl: 'waze://?q={query}',
    ),

    // Social Media
    'instagram': AppLaunchInfo(
      webUrl: 'https://www.instagram.com',
      deepLinkUrl: 'instagram://',
      searchWebUrl: 'https://www.instagram.com/explore/tags/{query}',
    ),
    'facebook': AppLaunchInfo(
      webUrl: 'https://www.facebook.com',
      deepLinkUrl: 'fb://',
      searchWebUrl: 'https://www.facebook.com/search/top?q={query}',
    ),
    'twitter': AppLaunchInfo(
      webUrl: 'https://twitter.com',
      deepLinkUrl: 'twitter://',
      searchWebUrl: 'https://twitter.com/search?q={query}',
    ),
    'x': AppLaunchInfo(
      webUrl: 'https://x.com',
      deepLinkUrl: 'twitter://',
      searchWebUrl: 'https://x.com/search?q={query}',
    ),
    'tiktok': AppLaunchInfo(
      webUrl: 'https://www.tiktok.com',
      deepLinkUrl: 'snssdk1233://',
      searchWebUrl: 'https://www.tiktok.com/search?q={query}',
    ),
    'reddit': AppLaunchInfo(
      webUrl: 'https://www.reddit.com',
      deepLinkUrl: 'reddit://',
      searchWebUrl: 'https://www.reddit.com/search/?q={query}',
    ),
    'snapchat': AppLaunchInfo(
      webUrl: 'https://www.snapchat.com',
      deepLinkUrl: 'snapchat://',
    ),
    'linkedin': AppLaunchInfo(
      webUrl: 'https://www.linkedin.com',
      deepLinkUrl: 'linkedin://',
      searchWebUrl: 'https://www.linkedin.com/search/results/all/?keywords={query}',
    ),
    'pinterest': AppLaunchInfo(
      webUrl: 'https://www.pinterest.com',
      deepLinkUrl: 'pinterest://',
      searchWebUrl: 'https://www.pinterest.com/search/pins/?q={query}',
    ),

    // Communication
    'whatsapp': AppLaunchInfo(
      webUrl: 'https://web.whatsapp.com',
      deepLinkUrl: 'whatsapp://',
    ),
    'telegram': AppLaunchInfo(
      webUrl: 'https://web.telegram.org',
      deepLinkUrl: 'tg://',
    ),
    'discord': AppLaunchInfo(
      webUrl: 'https://discord.com/app',
      deepLinkUrl: 'discord://',
    ),
    'zoom': AppLaunchInfo(
      webUrl: 'https://zoom.us/join',
      deepLinkUrl: 'zoomus://',
    ),
    'slack': AppLaunchInfo(
      webUrl: 'https://slack.com',
      deepLinkUrl: 'slack://',
    ),
    'messenger': AppLaunchInfo(
      webUrl: 'https://www.messenger.com',
      deepLinkUrl: 'fb-messenger://',
    ),

    // Productivity / Google
    'gmail': AppLaunchInfo(
      webUrl: 'https://mail.google.com',
      deepLinkUrl: 'googlegmail://',
    ),
    'google drive': AppLaunchInfo(
      webUrl: 'https://drive.google.com',
      deepLinkUrl: 'googledrive://',
    ),
    'google calendar': AppLaunchInfo(
      webUrl: 'https://calendar.google.com',
      deepLinkUrl: 'googlecalendar://',
    ),
    'google docs': AppLaunchInfo(
      webUrl: 'https://docs.google.com',
    ),
    'google sheets': AppLaunchInfo(
      webUrl: 'https://sheets.google.com',
    ),
    'google': AppLaunchInfo(
      webUrl: 'https://www.google.com',
      searchWebUrl: 'https://www.google.com/search?q={query}',
    ),

    // Shopping
    'amazon': AppLaunchInfo(
      webUrl: 'https://www.amazon.com',
      deepLinkUrl: 'com.amazon.mobile.shopping://',
      searchWebUrl: 'https://www.amazon.com/s?k={query}',
    ),
    'ebay': AppLaunchInfo(
      webUrl: 'https://www.ebay.com',
      deepLinkUrl: 'ebay://',
      searchWebUrl: 'https://www.ebay.com/sch/i.html?_nkw={query}',
    ),
    'walmart': AppLaunchInfo(
      webUrl: 'https://www.walmart.com',
      searchWebUrl: 'https://www.walmart.com/search?q={query}',
    ),
    'target': AppLaunchInfo(
      webUrl: 'https://www.target.com',
      searchWebUrl: 'https://www.target.com/s?searchTerm={query}',
    ),

    // Food & Delivery
    'uber eats': AppLaunchInfo(
      webUrl: 'https://www.ubereats.com',
      deepLinkUrl: 'ubereats://',
      searchWebUrl: 'https://www.ubereats.com/search?q={query}',
    ),
    'doordash': AppLaunchInfo(
      webUrl: 'https://www.doordash.com',
      deepLinkUrl: 'doordash://',
      searchWebUrl: 'https://www.doordash.com/search/store/{query}',
    ),
    'grubhub': AppLaunchInfo(
      webUrl: 'https://www.grubhub.com',
      searchWebUrl: 'https://www.grubhub.com/search?queryText={query}',
    ),

    // Ride Sharing
    'uber': AppLaunchInfo(
      webUrl: 'https://m.uber.com',
      deepLinkUrl: 'uber://',
    ),
    'lyft': AppLaunchInfo(
      webUrl: 'https://www.lyft.com',
      deepLinkUrl: 'lyft://',
    ),

    // News & Reading
    'news': AppLaunchInfo(
      webUrl: 'https://news.google.com',
      searchWebUrl: 'https://news.google.com/search?q={query}',
    ),
    'wikipedia': AppLaunchInfo(
      webUrl: 'https://www.wikipedia.org',
      searchWebUrl: 'https://en.wikipedia.org/wiki/Special:Search?search={query}',
    ),

    // Finance
    'venmo': AppLaunchInfo(
      webUrl: 'https://venmo.com',
      deepLinkUrl: 'venmo://',
    ),
    'paypal': AppLaunchInfo(
      webUrl: 'https://www.paypal.com',
      deepLinkUrl: 'paypal://',
    ),
    'cash app': AppLaunchInfo(
      webUrl: 'https://cash.app',
      deepLinkUrl: 'cashapp://',
    ),

    // System Apps (Android)
    'camera': AppLaunchInfo(
      webUrl: '', // No web URL for camera
      deepLinkUrl: 'intent:#Intent;action=android.media.action.STILL_IMAGE_CAMERA;end',
    ),
    'settings': AppLaunchInfo(
      webUrl: '', // No web URL for settings
      deepLinkUrl: 'intent:#Intent;action=android.settings.SETTINGS;end',
    ),
    'phone': AppLaunchInfo(
      webUrl: '', // No web URL for phone
      deepLinkUrl: 'tel:',
    ),
    'contacts': AppLaunchInfo(
      webUrl: '', // No web URL for contacts
      deepLinkUrl: 'content://contacts/people/',
    ),
    'calculator': AppLaunchInfo(
      webUrl: 'https://www.google.com/search?q=calculator',
      deepLinkUrl: 'intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.APP_CALCULATOR;end',
    ),

    // Entertainment
    'imdb': AppLaunchInfo(
      webUrl: 'https://www.imdb.com',
      deepLinkUrl: 'imdb://',
      searchWebUrl: 'https://www.imdb.com/find?q={query}',
    ),
    'yelp': AppLaunchInfo(
      webUrl: 'https://www.yelp.com',
      deepLinkUrl: 'yelp://',
      searchWebUrl: 'https://www.yelp.com/search?find_desc={query}',
    ),
  };

  /// Aliases for common variations
  static const Map<String, String> _aliases = {
    'yt': 'youtube',
    'insta': 'instagram',
    'ig': 'instagram',
    'fb': 'facebook',
    'whats app': 'whatsapp',
    'maps': 'google maps',
    'gmaps': 'google maps',
    'gmail mail': 'gmail',
    'email': 'gmail',
    'mail': 'gmail',
    'drive': 'google drive',
    'calendar': 'google calendar',
    'cal': 'google calendar',
    'docs': 'google docs',
    'sheets': 'google sheets',
    'snap': 'snapchat',
    'sc': 'snapchat',
    'tt': 'tiktok',
    'tik tok': 'tiktok',
    'prime': 'prime video',
    'amazon prime': 'prime video',
    'amazon video': 'prime video',
    'disney': 'disney+',
    'disney plus': 'disney+',
    'disneyplus': 'disney+',
    'twitter x': 'x',
    'elon musk app': 'x',
    'cash': 'cash app',
    'cashapp': 'cash app',
    'uber food': 'uber eats',
    'ubereats': 'uber eats',
    'door dash': 'doordash',
    'grub hub': 'grubhub',
    'apple music': 'apple music',
    'itunes': 'apple music',
    'wiki': 'wikipedia',
    'google search': 'google',
    'search': 'google',
  };

  /// Normalize app name (lowercase, remove extra spaces)
  static String _normalizeAppName(String appName) {
    return appName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Find app info by name (checks aliases too)
  static AppLaunchInfo? _findAppInfo(String appName) {
    final normalized = _normalizeAppName(appName);

    // Check direct match
    if (_apps.containsKey(normalized)) {
      return _apps[normalized];
    }

    // Check aliases
    if (_aliases.containsKey(normalized)) {
      final aliasTarget = _aliases[normalized]!;
      return _apps[aliasTarget];
    }

    // Fuzzy match - check if any app name contains the search term
    for (final entry in _apps.entries) {
      if (entry.key.contains(normalized) || normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Get the canonical app name
  static String _getCanonicalAppName(String appName) {
    final normalized = _normalizeAppName(appName);

    if (_apps.containsKey(normalized)) {
      return normalized;
    }

    if (_aliases.containsKey(normalized)) {
      return _aliases[normalized]!;
    }

    for (final entry in _apps.entries) {
      if (entry.key.contains(normalized) || normalized.contains(entry.key)) {
        return entry.key;
      }
    }

    return appName;
  }

  /// Format app name for display (title case)
  static String _formatAppName(String appName) {
    final canonical = _getCanonicalAppName(appName);
    // Handle special cases
    if (canonical == 'youtube') return 'YouTube';
    if (canonical == 'tiktok') return 'TikTok';
    if (canonical == 'whatsapp') return 'WhatsApp';
    if (canonical == 'linkedin') return 'LinkedIn';
    if (canonical == 'imdb') return 'IMDb';
    if (canonical == 'ebay') return 'eBay';
    if (canonical == 'disney+') return 'Disney+';
    if (canonical == 'x') return 'X';

    // Title case for others
    return canonical.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  /// Launch an app, optionally with a search query
  static Future<AppLaunchResult> launchApp(
    String appName, {
    String? searchQuery,
  }) async {
    final appInfo = _findAppInfo(appName);
    final displayName = _formatAppName(appName);

    if (appInfo == null) {
      // Unknown app - fall back to Google search
      debugPrint('AppLauncherService: Unknown app "$appName", falling back to Google search');
      final searchUrl = 'https://www.google.com/search?q=${Uri.encodeComponent('$appName app')}';
      try {
        final uri = Uri.parse(searchUrl);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          return AppLaunchResult(
            success: true,
            message: 'I couldn\'t find "$displayName" in my list, so I searched for it on Google.',
            appName: displayName,
          );
        }
      } catch (e) {
        debugPrint('AppLauncherService: Error searching for app: $e');
      }
      return AppLaunchResult(
        success: false,
        message: 'I couldn\'t find or open "$displayName".',
        appName: displayName,
      );
    }

    // Build the URL to launch
    String? urlToLaunch;

    if (searchQuery != null && searchQuery.isNotEmpty) {
      // Use search URL if available
      final encodedQuery = Uri.encodeComponent(searchQuery);
      if (appInfo.searchWebUrl != null) {
        urlToLaunch = appInfo.searchWebUrl!.replaceAll('{query}', encodedQuery);
      } else if (appInfo.webUrl.isNotEmpty) {
        // No search URL, just open the app
        urlToLaunch = appInfo.webUrl;
      }
    } else {
      // Just open the app
      urlToLaunch = appInfo.webUrl;
    }

    // Handle system apps that only have deep links
    if ((urlToLaunch == null || urlToLaunch.isEmpty) && appInfo.deepLinkUrl != null) {
      try {
        final uri = Uri.parse(appInfo.deepLinkUrl!);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          return AppLaunchResult(
            success: true,
            message: 'Opening $displayName.',
            appName: displayName,
          );
        }
      } catch (e) {
        debugPrint('AppLauncherService: Error launching deep link: $e');
      }
      return AppLaunchResult(
        success: false,
        message: 'I couldn\'t open $displayName. It might not be installed.',
        appName: displayName,
      );
    }

    if (urlToLaunch == null || urlToLaunch.isEmpty) {
      return AppLaunchResult(
        success: false,
        message: 'I don\'t have a way to open $displayName.',
        appName: displayName,
      );
    }

    // Try to launch
    try {
      final uri = Uri.parse(urlToLaunch);
      debugPrint('AppLauncherService: Launching $urlToLaunch');

      // Use externalApplication mode - Android will redirect to app if installed
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (launched) {
        if (searchQuery != null && searchQuery.isNotEmpty) {
          return AppLaunchResult(
            success: true,
            message: 'Opening $displayName with "$searchQuery".',
            appName: displayName,
          );
        } else {
          return AppLaunchResult(
            success: true,
            message: 'Opening $displayName.',
            appName: displayName,
          );
        }
      } else {
        return AppLaunchResult(
          success: false,
          message: 'I couldn\'t open $displayName.',
          appName: displayName,
        );
      }
    } catch (e) {
      debugPrint('AppLauncherService: Error launching URL: $e');
      return AppLaunchResult(
        success: false,
        message: 'Error opening $displayName: $e',
        appName: displayName,
      );
    }
  }

  /// Check if an app is known/supported
  static bool isKnownApp(String appName) {
    return _findAppInfo(appName) != null;
  }

  /// Get list of supported app names
  static List<String> get supportedApps => _apps.keys.toList();
}
