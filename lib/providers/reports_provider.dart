import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/reports_service.dart';

/// Provider for managing AI reports state
class ReportsProvider extends ChangeNotifier {
  List<Report> _liveReports = [];
  List<Report> _savedReports = [];
  List<String> _watchlist = [];
  Report? _pendingAnnouncement;
  Report? _lastAnnouncedReport;
  bool _isLoading = false;
  Timer? _pollingTimer;

  // Polling interval (5 minutes)
  static const _pollingInterval = Duration(minutes: 5);

  // ============================================================
  // GETTERS
  // ============================================================

  List<Report> get liveReports => _liveReports;
  List<Report> get savedReports => _savedReports;
  List<String> get watchlist => _watchlist;
  Report? get pendingAnnouncement => _pendingAnnouncement;
  Report? get lastAnnouncedReport => _lastAnnouncedReport;
  bool get isLoading => _isLoading;
  bool get hasUnreadReports => _pendingAnnouncement != null;

  // ============================================================
  // CALLBACKS
  // ============================================================

  /// Called when a report should be announced via TTS
  /// VoiceProvider listens to this
  Function(Report)? onAnnounceReport;

  /// Called when reports list changes
  VoidCallback? onReportsListChanged;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  /// Initialize the provider
  Future<void> init() async {
    debugPrint('ReportsProvider: Initializing');
    await loadReports();
    await loadWatchlist();
    _startPolling();
  }

  /// Start polling for new reports
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      checkForNewReports();
    });
    debugPrint('ReportsProvider: Started polling (every ${_pollingInterval.inMinutes} min)');

    // Also check immediately
    checkForNewReports();
  }

  /// Stop polling
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    debugPrint('ReportsProvider: Stopped polling');
  }

  // ============================================================
  // REPORTS LOADING
  // ============================================================

  /// Load all reports (live and saved)
  Future<void> loadReports() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load live and saved reports in parallel
      final results = await Future.wait([
        ReportsService.getLiveReports(),
        ReportsService.getSavedReports(),
      ]);

      _liveReports = results[0];
      _savedReports = results[1];

      debugPrint('ReportsProvider: Loaded ${_liveReports.length} live, ${_savedReports.length} saved reports');
    } catch (e) {
      debugPrint('ReportsProvider: Error loading reports: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check for new unannounced reports
  Future<void> checkForNewReports() async {
    try {
      // First, cleanup expired reports
      await ReportsService.cleanupExpiredReports();

      // Then check for unannounced reports
      final unannounced = await ReportsService.getUnannounced();

      if (unannounced.isNotEmpty) {
        debugPrint('ReportsProvider: Found ${unannounced.length} unannounced report(s)');

        // Take the most recent one for announcement
        final reportToAnnounce = unannounced.first;
        _pendingAnnouncement = reportToAnnounce;

        // Trigger announcement callback
        onAnnounceReport?.call(reportToAnnounce);

        // Refresh the reports list
        await loadReports();
      }
    } catch (e) {
      debugPrint('ReportsProvider: Error checking for new reports: $e');
    }
  }

  /// Mark a report as announced (called after TTS plays)
  Future<void> markAnnounced(String reportId) async {
    final success = await ReportsService.markAnnounced(reportId);
    if (success) {
      _lastAnnouncedReport = _pendingAnnouncement;
      _pendingAnnouncement = null;

      // Update local state
      final index = _liveReports.indexWhere((r) => r.id == reportId);
      if (index != -1) {
        _liveReports[index] = _liveReports[index].copyWith(
          announcedAt: DateTime.now(),
        );
      }

      notifyListeners();
    }
  }

  // ============================================================
  // REPORT ACTIONS
  // ============================================================

  /// Get a single report by ID
  Future<Report?> getReport(String reportId) async {
    return await ReportsService.getReport(reportId);
  }

  /// Get the full report for "tell me more" command
  Future<Report?> getFullReport(String reportId) async {
    return await ReportsService.getReport(reportId);
  }

  /// Save a report (prevents auto-deletion)
  Future<bool> saveReport(String reportId) async {
    final success = await ReportsService.saveReport(reportId);
    if (success) {
      // Move from live to saved
      final reportIndex = _liveReports.indexWhere((r) => r.id == reportId);
      if (reportIndex != -1) {
        final report = _liveReports[reportIndex].copyWith(
          savedAt: DateTime.now(),
        );
        _liveReports.removeAt(reportIndex);
        _savedReports.insert(0, report);
        onReportsListChanged?.call();
        notifyListeners();
      }
    }
    return success;
  }

  /// Unsave a report (returns to live status)
  Future<bool> unsaveReport(String reportId) async {
    final success = await ReportsService.unsaveReport(reportId);
    if (success) {
      // Move from saved to live
      final reportIndex = _savedReports.indexWhere((r) => r.id == reportId);
      if (reportIndex != -1) {
        final report = _savedReports[reportIndex].copyWith(savedAt: null);
        _savedReports.removeAt(reportIndex);
        _liveReports.insert(0, report);
        onReportsListChanged?.call();
        notifyListeners();
      }
    }
    return success;
  }

  /// Delete a report
  Future<bool> deleteReport(String reportId) async {
    final success = await ReportsService.deleteReport(reportId);
    if (success) {
      _liveReports.removeWhere((r) => r.id == reportId);
      _savedReports.removeWhere((r) => r.id == reportId);
      onReportsListChanged?.call();
      notifyListeners();
    }
    return success;
  }

  /// Copy report to a note
  Future<Note?> copyToNote(String reportId) async {
    return await ReportsService.copyToNote(reportId);
  }

  // ============================================================
  // WATCHLIST
  // ============================================================

  /// Load watchlist from Supabase
  Future<void> loadWatchlist() async {
    try {
      _watchlist = await ReportsService.getWatchlist();
      debugPrint('ReportsProvider: Loaded ${_watchlist.length} watchlist subjects');
      notifyListeners();
    } catch (e) {
      debugPrint('ReportsProvider: Error loading watchlist: $e');
    }
  }

  /// Add a subject to the watchlist
  Future<bool> addToWatchlist(String subject) async {
    if (subject.trim().isEmpty) return false;

    final success = await ReportsService.addToWatchlist(subject);
    if (success) {
      _watchlist.add(subject.trim());
      notifyListeners();
    }
    return success;
  }

  /// Remove a subject from the watchlist
  Future<bool> removeFromWatchlist(String subject) async {
    final success = await ReportsService.removeFromWatchlist(subject);
    if (success) {
      _watchlist.remove(subject);
      notifyListeners();
    }
    return success;
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
