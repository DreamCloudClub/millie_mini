import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'notes_service.dart';

/// Service for managing AI reports in Supabase
/// Reports are GLOBAL - user-specific state uses junction tables
class ReportsService {
  static final _supabase = Supabase.instance.client;
  static const String _reportsTable = 'reports';
  static const String _watchlistTable = 'watchlist';
  static const String _savedReportsTable = 'saved_reports';
  static const String _announcedReportsTable = 'announced_reports';
  static const String _newsSourcesTable = 'news_sources';

  // ============================================================
  // REPORTS QUERIES
  // ============================================================

  /// Get all live (non-expired) reports
  /// Optionally filter by categories from user's watchlist
  static Future<List<Report>> getLiveReports({
    List<String>? categories,
    String? category,
  }) async {
    try {
      final now = DateTime.now();

      var query = _supabase
          .from(_reportsTable)
          .select()
          .gte('expires_at', now.toIso8601String());

      // Filter by specific category if provided
      if (category != null && category.isNotEmpty) {
        query = query.eq('category', category.toLowerCase());
      }

      final response = await query.order('created_at', ascending: false);

      var reports = (response as List)
          .map((json) => Report.fromJson(json as Map<String, dynamic>))
          .toList();

      // If categories filter provided, filter locally
      if (categories != null && categories.isNotEmpty) {
        reports = reports.where((r) => categories.contains(r.category.toLowerCase())).toList();
      }

      debugPrint('ReportsService: Loaded ${reports.length} live reports');
      return reports;
    } catch (e) {
      debugPrint('ReportsService: Error loading live reports: $e');
      return [];
    }
  }

  /// Get reports filtered by category/subcategory
  static Future<List<Report>> getReportsByCategory({
    String? category,
    String? subcategory,
  }) async {
    try {
      final now = DateTime.now();

      var query = _supabase
          .from(_reportsTable)
          .select()
          .gte('expires_at', now.toIso8601String());

      if (category != null && category.isNotEmpty) {
        query = query.eq('category', category.toLowerCase());
      }
      if (subcategory != null && subcategory.isNotEmpty) {
        query = query.eq('subcategory', subcategory.toLowerCase());
      }

      final response = await query.order('created_at', ascending: false);

      return (response as List)
          .map((json) => Report.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('ReportsService: Error loading reports by category: $e');
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

  // ============================================================
  // SAVED REPORTS (Junction Table)
  // ============================================================

  /// Get IDs of reports the user has saved
  static Future<Set<String>> getSavedReportIds() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {};

      final response = await _supabase
          .from(_savedReportsTable)
          .select('report_id')
          .eq('user_id', userId);

      return (response as List)
          .map((json) => json['report_id'] as String)
          .toSet();
    } catch (e) {
      debugPrint('ReportsService: Error getting saved report IDs: $e');
      return {};
    }
  }

  /// Get saved reports for the user
  static Future<List<Report>> getSavedReports() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      // Join saved_reports with reports
      final response = await _supabase
          .from(_savedReportsTable)
          .select('report_id, saved_at, reports(*)')
          .eq('user_id', userId)
          .order('saved_at', ascending: false);

      final reports = <Report>[];
      for (final row in response as List) {
        final reportJson = row['reports'] as Map<String, dynamic>?;
        if (reportJson != null) {
          reports.add(Report.fromJson(reportJson));
        }
      }

      debugPrint('ReportsService: Loaded ${reports.length} saved reports');
      return reports;
    } catch (e) {
      debugPrint('ReportsService: Error loading saved reports: $e');
      return [];
    }
  }

  /// Save a report for the user
  static Future<bool> saveReport(String reportId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase.from(_savedReportsTable).insert({
        'user_id': userId,
        'report_id': reportId,
      });

      debugPrint('ReportsService: Saved report $reportId');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error saving report: $e');
      return false;
    }
  }

  /// Unsave a report for the user
  static Future<bool> unsaveReport(String reportId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from(_savedReportsTable)
          .delete()
          .eq('user_id', userId)
          .eq('report_id', reportId);

      debugPrint('ReportsService: Unsaved report $reportId');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error unsaving report: $e');
      return false;
    }
  }

  /// Check if a report is saved by the user
  static Future<bool> isReportSaved(String reportId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from(_savedReportsTable)
          .select('id')
          .eq('user_id', userId)
          .eq('report_id', reportId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('ReportsService: Error checking saved status: $e');
      return false;
    }
  }

  // ============================================================
  // ANNOUNCED REPORTS (Junction Table)
  // ============================================================

  /// Get IDs of reports that have been announced to the user
  static Future<Set<String>> getAnnouncedReportIds() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {};

      final response = await _supabase
          .from(_announcedReportsTable)
          .select('report_id')
          .eq('user_id', userId);

      return (response as List)
          .map((json) => json['report_id'] as String)
          .toSet();
    } catch (e) {
      debugPrint('ReportsService: Error getting announced report IDs: $e');
      return {};
    }
  }

  /// Mark a report as announced to the user
  static Future<bool> markAnnounced(String reportId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase.from(_announcedReportsTable).insert({
        'user_id': userId,
        'report_id': reportId,
      });

      debugPrint('ReportsService: Marked report $reportId as announced');
      return true;
    } catch (e) {
      // Likely duplicate - already announced
      debugPrint('ReportsService: Error marking announced (may be duplicate): $e');
      return false;
    }
  }

  /// Check if a report has been announced to the user
  static Future<bool> isReportAnnounced(String reportId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from(_announcedReportsTable)
          .select('id')
          .eq('user_id', userId)
          .eq('report_id', reportId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('ReportsService: Error checking announced status: $e');
      return false;
    }
  }

  /// Get unannounced reports matching user's watchlist categories
  /// Only returns reports created in the last hour that haven't been announced
  static Future<List<Report>> getUnannounced({
    List<String>? categories,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      // Get already announced report IDs
      final announcedIds = await getAnnouncedReportIds();

      // Get live reports from the last hour
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final response = await _supabase
          .from(_reportsTable)
          .select()
          .gte('created_at', oneHourAgo.toIso8601String())
          .order('created_at', ascending: false);

      var reports = (response as List)
          .map((json) => Report.fromJson(json as Map<String, dynamic>))
          .where((r) => !announcedIds.contains(r.id))
          .toList();

      // Filter by watchlist categories if provided
      if (categories != null && categories.isNotEmpty) {
        reports = reports.where((r) => categories.contains(r.category.toLowerCase())).toList();
      }

      debugPrint('ReportsService: Found ${reports.length} unannounced reports');
      return reports;
    } catch (e) {
      debugPrint('ReportsService: Error getting unannounced reports: $e');
      return [];
    }
  }

  // ============================================================
  // REPORT MANAGEMENT
  // ============================================================

  /// Update the audio URL for a report (after TTS generation)
  static Future<bool> updateAudioUrl(String reportId, String audioUrl) async {
    try {
      await _supabase
          .from(_reportsTable)
          .update({'audio_url': audioUrl})
          .eq('id', reportId);

      debugPrint('ReportsService: Updated audio URL for report $reportId');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error updating audio URL: $e');
      return false;
    }
  }

  /// Delete a report (admin only - reports are global)
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

  /// Get all watchlist items for the user
  static Future<List<WatchlistItem>> getWatchlist() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from(_watchlistTable)
          .select()
          .eq('user_id', userId)
          .order('category', ascending: true)
          .order('subcategory', ascending: true);

      final items = (response as List)
          .map((json) => WatchlistItem.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('ReportsService: Loaded ${items.length} watchlist items');
      return items;
    } catch (e) {
      debugPrint('ReportsService: Error loading watchlist: $e');
      return [];
    }
  }

  /// Get enabled watchlist categories as a list of category strings
  static Future<List<String>> getEnabledWatchlistCategories() async {
    try {
      final watchlist = await getWatchlist();
      return watchlist
          .where((w) => w.enabled)
          .map((w) => w.category.toLowerCase())
          .toSet()
          .toList();
    } catch (e) {
      debugPrint('ReportsService: Error getting enabled categories: $e');
      return [];
    }
  }

  /// Add a category/subcategory to the watchlist
  static Future<bool> addToWatchlist({
    required String category,
    String? subcategory,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return false;
      }

      await _supabase.from(_watchlistTable).insert({
        'user_id': userId,
        'category': category.toLowerCase().trim(),
        'subcategory': subcategory?.toLowerCase().trim(),
        'enabled': true,
      });

      debugPrint('ReportsService: Added "$category/$subcategory" to watchlist');
      return true;
    } catch (e) {
      // Likely a duplicate (unique constraint violation)
      debugPrint('ReportsService: Error adding to watchlist: $e');
      return false;
    }
  }

  /// Remove a category/subcategory from the watchlist
  static Future<bool> removeFromWatchlist({
    required String category,
    String? subcategory,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('ReportsService: No user logged in');
        return false;
      }

      var query = _supabase
          .from(_watchlistTable)
          .delete()
          .eq('user_id', userId)
          .eq('category', category.toLowerCase());

      if (subcategory != null) {
        query = query.eq('subcategory', subcategory.toLowerCase());
      } else {
        query = query.isFilter('subcategory', null);
      }

      await query;

      debugPrint('ReportsService: Removed "$category/$subcategory" from watchlist');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error removing from watchlist: $e');
      return false;
    }
  }

  /// Toggle enabled state of a watchlist item
  static Future<bool> toggleWatchlistItem(String itemId, bool enabled) async {
    try {
      await _supabase
          .from(_watchlistTable)
          .update({'enabled': enabled})
          .eq('id', itemId);

      debugPrint('ReportsService: Toggled watchlist item $itemId to $enabled');
      return true;
    } catch (e) {
      debugPrint('ReportsService: Error toggling watchlist item: $e');
      return false;
    }
  }

  // ============================================================
  // CATEGORIES (from news_sources)
  // ============================================================

  /// Get available categories - predefined list matching reporter.js
  static Future<List<NewsCategory>> getAvailableCategories() async {
    return _getCategoryDefinitions();
  }

  /// Predefined category/subcategory list (matches reporter.js CATEGORIES)
  /// Order: technology, business, politics, science, health, sports, entertainment, lifestyle, weather, kids
  static List<NewsCategory> _getCategoryDefinitions() {
    final definitions = [
      ('technology', ['ai', 'robots', 'drones', 'computers', 'devices', 'gaming', 'software', 'hardware', 'crypto', 'startups']),
      ('business', ['markets', 'finance', 'startups', 'crypto', 'real estate', 'economy']),
      ('politics', ['us', 'world', 'elections', 'policy']),
      ('science', ['space', 'environment', 'biology', 'physics', 'chemistry', 'research']),
      ('health', ['medicine', 'fitness', 'nutrition', 'mental health', 'research']),
      ('sports', ['football', 'basketball', 'soccer', 'baseball', 'olympics', 'esports', 'mma', 'tennis']),
      ('entertainment', ['movies', 'tv', 'music', 'gaming', 'celebrities', 'streaming']),
      ('lifestyle', ['food', 'travel', 'fashion', 'home', 'relationships']),
      ('weather', ['forecast', 'storms', 'climate']),
      ('kids', ['animals', 'science', 'games', 'stories', 'learning']),
    ];

    final categories = <NewsCategory>[];

    for (final (category, subcategories) in definitions) {
      // Add main category
      categories.add(NewsCategory(category: category));

      // Add subcategories
      for (final sub in subcategories) {
        categories.add(NewsCategory(category: category, subcategory: sub));
      }
    }

    return categories;
  }

  /// Get distinct categories from reports (for tab filtering)
  static Future<List<String>> getReportCategories() async {
    try {
      final now = DateTime.now();

      final response = await _supabase
          .from(_reportsTable)
          .select('category')
          .gte('expires_at', now.toIso8601String());

      final categories = (response as List)
          .map((json) => json['category'] as String)
          .toSet()
          .toList()
        ..sort();

      debugPrint('ReportsService: Found ${categories.length} report categories');
      return categories;
    } catch (e) {
      debugPrint('ReportsService: Error getting report categories: $e');
      return [];
    }
  }
}
