import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Service for managing report schedules in Supabase
/// Schedules sync across all devices
class ReportSettingsService {
  static final _supabase = Supabase.instance.client;
  static const String _schedulesTable = 'reports_schedules';

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
}
