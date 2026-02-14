import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

/// Service to track monthly token usage and enforce limits
class UsageTrackingService {
  static const int _holderLimit = 500000; // 500K tokens (~$5/month)
  static const int _basicLimit = 500000;  // 500K tokens (~$6/month)
  static const int _proLimit = 1000000;   // 1M tokens (~$12/month)

  /// Get token limit for a subscription status
  static int getTokenLimit(AIServiceStatus status) {
    switch (status) {
      case AIServiceStatus.holder:
        return _holderLimit;
      case AIServiceStatus.basic:
        return _basicLimit;
      case AIServiceStatus.pro:
        return _proLimit;
      case AIServiceStatus.trial:
        return _basicLimit; // Trial gets basic limit
      default:
        return 0; // No access
    }
  }

  /// Check if user can make an API call (has tokens remaining)
  /// Returns usage info including whether the call can proceed
  static Future<Map<String, dynamic>> checkUsageLimit({
    required String userId,
    required String userEmail,
    required AIServiceStatus subscriptionStatus,
    int tokensNeeded = 0,
  }) async {
    try {
      final response = await SupabaseConfig.client.rpc(
        'check_usage_limit',
        params: {
          'p_user_id': userId,
          'p_user_email': userEmail,
          'p_subscription_status': _statusToString(subscriptionStatus),
          'p_tokens_needed': tokensNeeded,
        },
      );
      
      if (response == null) {
        throw Exception('Null response from check_usage_limit');
      }

      // RPC returns dynamic, convert to Map
      if (response is Map<String, dynamic>) {
        return response;
      } else if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      // Fallback if RPC doesn't return expected format
      return {
        'can_proceed': false,
        'tokens_used': 0,
        'token_limit': getTokenLimit(subscriptionStatus),
        'tokens_remaining': 0,
        'subscription_status': _statusToString(subscriptionStatus),
      };
    } catch (e) {
      debugPrint('Error checking usage limit: $e');
      // On error, allow the call but log it
      return {
        'can_proceed': true, // Allow on error to avoid blocking
        'tokens_used': 0,
        'token_limit': getTokenLimit(subscriptionStatus),
        'tokens_remaining': getTokenLimit(subscriptionStatus),
        'subscription_status': _statusToString(subscriptionStatus),
        'error': e.toString(),
      };
    }
  }

  /// Record token usage after an API call
  static Future<void> recordUsage({
    required String userId,
    required String userEmail,
    required AIServiceStatus subscriptionStatus,
    required int tokensUsed,
  }) async {
    try {
      await SupabaseConfig.client.rpc(
        'record_usage',
        params: {
          'p_user_id': userId,
          'p_user_email': userEmail,
          'p_subscription_status': _statusToString(subscriptionStatus),
          'p_tokens_used': tokensUsed,
        },
      );
    } catch (e) {
      debugPrint('Error recording usage: $e');
      // Don't throw - usage tracking shouldn't block the app
    }
  }

  /// Get current month's usage stats
  /// Optionally pass userEmail and subscriptionStatus to create record if needed
  static Future<Map<String, dynamic>> getCurrentUsage(
    String userId, {
    String? userEmail,
    AIServiceStatus? subscriptionStatus,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_user_id': userId,
      };
      
      // Add optional parameters if provided
      if (userEmail != null) {
        params['p_user_email'] = userEmail;
      }
      
      if (subscriptionStatus != null) {
        params['p_subscription_status'] = _statusToString(subscriptionStatus);
      }
      
      final response = await SupabaseConfig.client.rpc(
        'get_current_usage',
        params: params,
      );
      
      if (response == null) {
        throw Exception('Null response from get_current_usage');
      }

      // RPC returns dynamic, convert to Map
      if (response is Map<String, dynamic>) {
        return response;
      } else if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      // Fallback - calculate limit if we have subscription status
      final tokenLimit = subscriptionStatus != null 
          ? getTokenLimit(subscriptionStatus)
          : 0;

      return {
        'tokens_used': 0,
        'token_limit': tokenLimit,
        'tokens_remaining': tokenLimit,
        'subscription_status': subscriptionStatus != null 
            ? _statusToString(subscriptionStatus)
            : 'inactive',
        'year_month': _getCurrentYearMonth(),
      };
    } catch (e) {
      debugPrint('Error getting current usage: $e');
      
      // Fallback - calculate limit if we have subscription status
      final tokenLimit = subscriptionStatus != null 
          ? getTokenLimit(subscriptionStatus)
          : 0;
      
      return {
        'tokens_used': 0,
        'token_limit': tokenLimit,
        'tokens_remaining': tokenLimit,
        'subscription_status': subscriptionStatus != null 
            ? _statusToString(subscriptionStatus)
            : 'inactive',
        'year_month': _getCurrentYearMonth(),
        'error': e.toString(),
      };
    }
  }

  /// Convert AIServiceStatus to string for database
  static String _statusToString(AIServiceStatus status) {
    switch (status) {
      case AIServiceStatus.holder:
        return 'holder';
      case AIServiceStatus.basic:
        return 'basic';
      case AIServiceStatus.pro:
        return 'pro';
      case AIServiceStatus.active:
        return 'active';
      case AIServiceStatus.trial:
        return 'trial';
      case AIServiceStatus.inactive:
        return 'inactive';
      case AIServiceStatus.pending:
        return 'pending';
      case AIServiceStatus.expired:
        return 'expired';
      case AIServiceStatus.notFound:
        return 'notFound';
      case AIServiceStatus.unknown:
        return 'unknown';
    }
  }

  /// Get current year-month string
  static String _getCurrentYearMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Format token count for display
  static String formatTokens(int tokens) {
    if (tokens >= 1000000) {
      final millions = tokens / 1000000;
      // Remove .0 for whole numbers
      return millions % 1 == 0 
          ? '${millions.toInt()}M'
          : '${millions.toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      final thousands = tokens / 1000;
      // Remove .0 for whole numbers
      return thousands % 1 == 0 
          ? '${thousands.toInt()}K'
          : '${thousands.toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }
}

