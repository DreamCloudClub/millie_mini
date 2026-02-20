import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'notes_service.dart';

/// Service for managing AI reports in Supabase
class ReportsService {
  static final _supabase = Supabase.instance.client;
  static const String _reportsTable = 'reports';
  static const String _watchlistTable = 'watchlist';

  // ============================================================
  // REPORTS CRUD
  // ============================================================

  /// Get unannounced reports (where announced_at IS NULL and < 1hr old)
  static Future<List<Report>> getUnannounced() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return [];
      }

      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final response = await _supabase
          .from(_reportsTable)
          .select()
          .eq('user_id', userId)
          .isFilter('announced_at', null)
          .gte('created_at', oneHourAgo.toIso8601String())
          .order('created_at', ascending: false);

      final reports = (response as List)
          .map((json) => Report.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('ReportsService: Found ${reports.length} unannounced reports');
      return reports;
    } catch (e) {
      debugPrint('ReportsService: Error getting unannounced reports: $e');
      return [];
    }
  }

  /// Mark a report as announced
  static Future<bool> markAnnounced(String reportId) async {
    try {
      await _supabase
          .from(_reportsTable)
          .update({'announced_at': DateTime.now().toIso8601String()})
          .eq('id', reportId);

      debugPrint('ReportsService: Marked report $reportId as announced');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error marking report announced: $e');
      return false;
    }
  }

  /// Get live reports (non-saved, non-expired)
  static Future<List<Report>> getLiveReports() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return [];
      }

      final now = DateTime.now();

      final response = await _supabase
          .from(_reportsTable)
          .select()
          .eq('user_id', userId)
          .isFilter('saved_at', null)
          .gte('expires_at', now.toIso8601String())
          .order('created_at', ascending: false);

      final reports = (response as List)
          .map((json) => Report.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('ReportsService: Loaded ${reports.length} live reports');
      return reports;
    } catch (e) {
      debugPrint('ReportsService: Error loading live reports: $e');
      return [];
    }
  }

  /// Get saved reports
  static Future<List<Report>> getSavedReports() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from(_reportsTable)
          .select()
          .eq('user_id', userId)
          .not('saved_at', 'is', null)
          .order('saved_at', ascending: false);

      final reports = (response as List)
          .map((json) => Report.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('ReportsService: Loaded ${reports.length} saved reports');
      return reports;
    } catch (e) {
      debugPrint('ReportsService: Error loading saved reports: $e');
      return [];
    }
  }

  /// Get a single report by ID
  static Future<Report?> getReport(String reportId) async {
    try {
      final response = await _supabase
          .from(_reportsTable)
          .select()
          .eq('id', reportId)
          .single();

      return Report.fromJson(response);
    } catch (e) {
      debugPrint('ReportsService: Error loading report $reportId: $e');
      return null;
    }
  }

  /// Save a report (prevents auto-deletion)
  static Future<bool> saveReport(String reportId) async {
    try {
      await _supabase
          .from(_reportsTable)
          .update({'saved_at': DateTime.now().toIso8601String()})
          .eq('id', reportId);

      debugPrint('ReportsService: Saved report $reportId');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error saving report: $e');
      return false;
    }
  }

  /// Unsave a report (returns to live status)
  static Future<bool> unsaveReport(String reportId) async {
    try {
      await _supabase
          .from(_reportsTable)
          .update({'saved_at': null})
          .eq('id', reportId);

      debugPrint('ReportsService: Unsaved report $reportId');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error unsaving report: $e');
      return false;
    }
  }

  /// Delete a report
  static Future<bool> deleteReport(String reportId) async {
    try {
      await _supabase
          .from(_reportsTable)
          .delete()
          .eq('id', reportId);

      debugPrint('ReportsService: Deleted report $reportId');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error deleting report $reportId: $e');
      return false;
    }
  }

  /// Cleanup expired unsaved reports (older than 48 hours)
  static Future<int> cleanupExpiredReports() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      final now = DateTime.now();

      // Delete unsaved reports where expires_at < now
      final response = await _supabase
          .from(_reportsTable)
          .delete()
          .eq('user_id', userId)
          .isFilter('saved_at', null)
          .lt('expires_at', now.toIso8601String())
          .select();

      final deletedCount = (response as List).length;
      if (deletedCount > 0) {
        debugPrint('ReportsService: Cleaned up $deletedCount expired reports');
      }
      return deletedCount;
    } catch (e) {
      debugPrint('ReportsService: Error cleaning up expired reports: $e');
      return 0;
    }
  }

  /// Copy report content to a note
  static Future<Note?> copyToNote(String reportId) async {
    try {
      final report = await getReport(reportId);
      if (report == null) {
        debugPrint('ReportsService: Report $reportId not found');
        return null;
      }

      // Create note with report content
      final note = await NotesService.createNote(
        title: report.title,
        content: '${report.summary}\n\n${report.content}',
      );

      if (note != null) {
        debugPrint('ReportsService: Copied report to note ${note.id}');
      }
      return note;
    } catch (e) {
      debugPrint('ReportsService: Error copying report to note: $e');
      return null;
    }
  }

  // ============================================================
  // WATCHLIST CRUD
  // ============================================================

  /// Get all watchlist subjects for the user
  static Future<List<String>> getWatchlist() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from(_watchlistTable)
          .select('subject')
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      final subjects = (response as List)
          .map((json) => json['subject'] as String)
          .toList();

      debugPrint('ReportsService: Loaded ${subjects.length} watchlist subjects');
      return subjects;
    } catch (e) {
      debugPrint('ReportsService: Error loading watchlist: $e');
      return [];
    }
  }

  /// Add a subject to the watchlist
  static Future<bool> addToWatchlist(String subject) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return false;
      }

      await _supabase.from(_watchlistTable).insert({
        'user_id': userId,
        'subject': subject.trim(),
      });

      debugPrint('ReportsService: Added "$subject" to watchlist');
      return true;
    } catch (e) {
      // Likely a duplicate (unique constraint violation)
      debugPrint('ReportsService: Error adding to watchlist: $e');
      return false;
    }
  }

  /// Remove a subject from the watchlist
  static Future<bool> removeFromWatchlist(String subject) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return false;
      }

      await _supabase
          .from(_watchlistTable)
          .delete()
          .eq('user_id', userId)
          .eq('subject', subject);

      debugPrint('ReportsService: Removed "$subject" from watchlist');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error removing from watchlist: $e');
      return false;
    }
  }
}
