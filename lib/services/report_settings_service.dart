import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Service for managing report schedules in Supabase
/// Schedules sync across all devices
class ReportSettingsService {
  static final _supabase = Supabase.instance.client;
  static const String _schedulesTable = 'reports_schedules';
  static const String _settingsTable = 'report_settings';

  // ============================================================
  // CATEGORY SCHEDULES CRUD
  // ============================================================

  /// Get all category schedules for the user
  static Future<List<CategorySchedule>> getSchedules() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportSettingsService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from(_schedulesTable)
          .select()
          .eq('user_id', userId)
          .order('start_time', ascending: true);

      final schedules = (response as List)
          .map((json) => CategorySchedule.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('ReportSettingsService: Loaded ${schedules.length} schedules');
      return schedules;
    } catch (e) {
      debugPrint('ReportSettingsService: Error loading schedules: $e');
      return [];
    }
  }

  /// Get enabled schedules that are currently active
  static Future<List<CategorySchedule>> getActiveSchedules() async {
    try {
      final schedules = await getSchedules();
      return schedules.where((s) => s.enabled && s.isActiveNow()).toList();
    } catch (e) {
      debugPrint('ReportSettingsService: Error getting active schedules: $e');
      return [];
    }
  }

  /// Add a new category schedule
  static Future<CategorySchedule?> addSchedule(CategorySchedule schedule) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportSettingsService: No user logged in');
        return null;
      }

      final response = await _supabase
          .from(_schedulesTable)
          .insert(schedule.toInsertJson())
          .select()
          .single();

      debugPrint('ReportSettingsService: Added schedule for ${schedule.categoryDisplay}');
      return CategorySchedule.fromJson(response);
    } catch (e) {
      debugPrint('ReportSettingsService: Error adding schedule: $e');
      return null;
    }
  }

  /// Update an existing schedule
  static Future<bool> updateSchedule(CategorySchedule schedule) async {
    try {
      await _supabase
          .from(_schedulesTable)
          .update(schedule.toUpdateJson())
          .eq('id', schedule.id);

      debugPrint('ReportSettingsService: Updated schedule ${schedule.id}');
      return true;
    } catch (e) {
      debugPrint('ReportSettingsService: Error updating schedule: $e');
      return false;
    }
  }

  /// Delete a schedule
  static Future<bool> deleteSchedule(String scheduleId) async {
    try {
      await _supabase
          .from(_schedulesTable)
          .delete()
          .eq('id', scheduleId);

      debugPrint('ReportSettingsService: Deleted schedule $scheduleId');
      return true;
    } catch (e) {
      debugPrint('ReportSettingsService: Error deleting schedule: $e');
      return false;
    }
  }

  /// Toggle a schedule's enabled state
  static Future<bool> toggleSchedule(String scheduleId, bool enabled) async {
    try {
      await _supabase
          .from(_schedulesTable)
          .update({'enabled': enabled})
          .eq('id', scheduleId);

      debugPrint('ReportSettingsService: Toggled schedule $scheduleId to $enabled');
      return true;
    } catch (e) {
      debugPrint('ReportSettingsService: Error toggling schedule: $e');
      return false;
    }
  }

  /// Get categories that have active schedules right now
  static Future<Set<String>> getActiveCategories() async {
    try {
      final activeSchedules = await getActiveSchedules();
      final categories = <String>{};

      for (final schedule in activeSchedules) {
        if (schedule.categories.isEmpty) {
          // Empty categories means all categories from watchlist
          return {'all'};
        }
        categories.addAll(schedule.categories);
      }

      return categories;
    } catch (e) {
      debugPrint('ReportSettingsService: Error getting active categories: $e');
      return {};
    }
  }

  // ============================================================
  // DISPLAY SIZE SETTINGS
  // ============================================================

  /// Get the user's display size preference
  static Future<DisplaySize> getDisplaySize() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportSettingsService: No user logged in');
        return DisplaySize.normal;
      }

      final response = await _supabase
          .from(_settingsTable)
          .select('display_size')
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return DisplaySize.normal;
      }

      return DisplaySizeExtension.fromString(response['display_size'] as String?);
    } catch (e) {
      debugPrint('ReportSettingsService: Error getting display size: $e');
      return DisplaySize.normal;
    }
  }

  /// Update the user's display size preference
  static Future<bool> updateDisplaySize(DisplaySize displaySize) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportSettingsService: No user logged in');
        return false;
      }

      // Upsert to handle case where settings row doesn't exist yet
      // Include enabled field with default value for new row inserts
      await _supabase
          .from(_settingsTable)
          .upsert({
            'user_id': userId,
            'enabled': true,
            'display_size': displaySize.name,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id');

      debugPrint('ReportSettingsService: Updated display size to ${displaySize.name}');
      return true;
    } catch (e) {
      debugPrint('ReportSettingsService: Error updating display size: $e');
      return false;
    }
  }
}
