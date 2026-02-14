import 'package:flutter/material.dart';

class AppColors {
  // Brand colors
  static const Color dreamCloudBlue = Color(0xFF30C1FF);
  static const Color faceBackground = Color(0xFF000000); // Pure black
  static const Color primaryOrange = Color(0xFFFF6B35);
  
  // UI colors
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textLight = Color(0xFF999999);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF388E3C);
  
  // Button colors
  static const Color buttonPrimary = primaryOrange;
  static const Color buttonSecondary = Color(0xFF424242);
  static const Color buttonDisabled = Color(0xFFBDBDBD);
  
  // Face colors
  static const Color eyeDefault = Colors.white;
  static const Color mouthDefault = Colors.white;
}

class AppTextStyles {
  // Using system font since custom fonts aren't bundled
  static const String fontFamily = 'SF Pro Display';
  
  static const TextStyle heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle heading2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );
  
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
  
  static const TextStyle label = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppBorderRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double card = 10;
}

// Voice control keywords
class VoiceTriggers {
  static const List<String> pauseTriggers = [
    'pause',
    'stop',
    'millie pause',
    'millie stop',
    'hold on',
    'be quiet',
  ];
  
  static const List<String> resumeTriggers = [
    'hey millie',
    'millie',
  ];
}

// Storage keys
class StorageKeys {
  static const String userProfile = 'user_profile';
  static const String agents = 'agents';
  static const String personalities = 'personalities';
  static const String aiServices = 'ai_services';
  static const String activeAgentId = 'active_agent_id';
  static const String isLoggedIn = 'is_logged_in';
  static const String authToken = 'auth_token';
  static const String porcupineAccessKey = 'porcupine_access_key';
}
