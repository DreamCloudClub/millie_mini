import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/reports_service.dart';
import '../services/report_settings_service.dart';

/// Provider for managing AI reports state
class ReportsProvider extends ChangeNotifier {
  List<Report> _liveReports = [];
  List<Report> _savedReports = [];
  List<WatchlistItem> _watchlist = [];
  List<NewsCategory> _availableCategories = [];
  Set<String> _savedReportIds = {};
  Set<String> _announcedReportIds = {};

  // Schedules
  List<CategorySchedule> _schedules = [];

  // Category filtering
  String? _selectedCategory;
  List<String> _reportCategories = [];

  // Sort order: true = newest first, false = oldest first
  bool _newestFirst = true;

  // Announcement state
  Report? _pendingAnnouncement;
  Report? _lastAnnouncedReport;
  List<Report> _pendingReportQueue = [];

  bool _isLoading = false;
  Timer? _pollingTimer;

  // Polling interval (5 minutes)
  static const _pollingInterval = Duration(minutes: 5);

  // ============================================================
  // GETTERS
  // ============================================================

  List<Report> get liveReports => _liveReports;
  List<Report> get savedReports => _savedReports;
  List<WatchlistItem> get watchlist => _watchlist;
  List<WatchlistItem> get enabledWatchlist =>
      _watchlist.where((w) => w.enabled).toList();
  List<NewsCategory> get availableCategories => _availableCategories;
  List<CategorySchedule> get schedules => _schedules;
  List<CategorySchedule> get enabledSchedules =>
      _schedules.where((s) => s.enabled).toList();
  String? get selectedCategory => _selectedCategory;
  List<String> get reportCategories => _reportCategories;
  bool get newestFirst => _newestFirst;

  Report? get pendingAnnouncement => _pendingAnnouncement;
  Report? get lastAnnouncedReport => _lastAnnouncedReport;
  List<Report> get pendingReportQueue => _pendingReportQueue;
  bool get isLoading => _isLoading;
  bool get hasUnreadReports => _pendingAnnouncement != null || _pendingReportQueue.isNotEmpty;

  /// Whether announcements are enabled (true if any schedules are enabled)
  bool get announcementsEnabled => enabledSchedules.isNotEmpty;

  /// Number of active schedules
  int get activeScheduleCount => enabledSchedules.length;

  /// Filtered live reports based on selected category
  /// Live = not announced AND not saved
  List<Report> get filteredLiveReports {
    final seenIds = <String>{};
    var reports = _liveReports.where((r) {
      if (seenIds.contains(r.id)) return false; // Deduplicate
      seenIds.add(r.id);
      return !_announcedReportIds.contains(r.id) && !_savedReportIds.contains(r.id);
    }).toList();

    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      reports = reports
          .where((r) => r.category.toLowerCase() == _selectedCategory!.toLowerCase())
          .toList();
    }

    // Apply sort order
    reports.sort((a, b) => _newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));

    return reports;
  }

  /// History reports = announced but NOT saved
  List<Report> get historyReports {
    final seenIds = <String>{};
    var reports = _liveReports.where((r) {
      if (seenIds.contains(r.id)) return false; // Deduplicate
      seenIds.add(r.id);
      return _announcedReportIds.contains(r.id) && !_savedReportIds.contains(r.id);
    }).toList();

    // Apply sort order
    reports.sort((a, b) => _newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));

    return reports;
  }

  /// Toggle sort order between newest first and oldest first
  void toggleSortOrder() {
    _newestFirst = !_newestFirst;
    notifyListeners();
  }

  /// Set sort order explicitly
  void setSortOrder({required bool newestFirst}) {
    _newestFirst = newestFirst;
    notifyListeners();
  }

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

    await Future.wait([
      loadSchedules(),
      loadReports(),
      loadWatchlist(),
      loadAvailableCategories(),
      _loadUserState(),
    ]);

    _startPolling();
  }

  /// Load user-specific state (saved/announced IDs)
  Future<void> _loadUserState() async {
    try {
      final results = await Future.wait([
        ReportsService.getSavedReportIds(),
        ReportsService.getAnnouncedReportIds(),
      ]);

      _savedReportIds = results[0];
      _announcedReportIds = results[1];

      debugPrint('ReportsProvider: Loaded ${_savedReportIds.length} saved, ${_announcedReportIds.length} announced IDs');
    } catch (e) {
      debugPrint('ReportsProvider: Error loading user state: $e');
    }
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
  // SCHEDULES MANAGEMENT
  // ============================================================

  /// Load user's category schedules
  Future<void> loadSchedules() async {
    try {
      _schedules = await ReportSettingsService.getSchedules();
      debugPrint('ReportsProvider: Loaded ${_schedules.length} schedules');
      notifyListeners();
    } catch (e) {
      debugPrint('ReportsProvider: Error loading schedules: $e');
    }
  }

  /// Add a new schedule
  Future<bool> addSchedule(CategorySchedule schedule) async {
    final result = await ReportSettingsService.addSchedule(schedule);
    if (result != null) {
      _schedules.add(result);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Update an existing schedule
  Future<bool> updateSchedule(CategorySchedule schedule) async {
    final success = await ReportSettingsService.updateSchedule(schedule);
    if (success) {
      final index = _schedules.indexWhere((s) => s.id == schedule.id);
      if (index != -1) {
        _schedules[index] = schedule;
        notifyListeners();
      }
    }
    return success;
  }

  /// Delete a schedule
  Future<bool> deleteSchedule(String scheduleId) async {
    final success = await ReportSettingsService.deleteSchedule(scheduleId);
    if (success) {
      _schedules.removeWhere((s) => s.id == scheduleId);
      notifyListeners();
    }
    return success;
  }

  /// Toggle a schedule's enabled state
  Future<bool> toggleSchedule(String scheduleId, bool enabled) async {
    final success = await ReportSettingsService.toggleSchedule(scheduleId, enabled);
    if (success) {
      final index = _schedules.indexWhere((s) => s.id == scheduleId);
      if (index != -1) {
        _schedules[index] = _schedules[index].copyWith(enabled: enabled);
        notifyListeners();
      }
    }
    return success;
  }

  /// Check if any schedule is currently active
  bool shouldAnnounceNow() {
    if (!announcementsEnabled) return false;
    return _schedules.any((s) => s.isActiveNow());
  }

  /// Check if a specific category should be announced now
  bool shouldAnnounceCategoryNow(String category) {
    if (!announcementsEnabled) return false;

    return _schedules.any((s) {
      if (!s.isActiveNow()) return false;
      // Empty categories means all categories
      if (s.categories.isEmpty) return true;
      return s.categories.any((c) => c.toLowerCase() == category.toLowerCase());
    });
  }

  /// Get categories that should be announced now
  Set<String> getActiveAnnouncementCategories() {
    if (!announcementsEnabled) return {};

    final activeSchedules = _schedules.where((s) => s.isActiveNow());
    final categories = <String>{};

    for (final schedule in activeSchedules) {
      // Empty categories means all categories from watchlist
      if (schedule.categories.isEmpty) {
        return {'all'};
      }
      for (final cat in schedule.categories) {
        categories.add(cat.toLowerCase());
      }
    }

    return categories;
  }

  // ============================================================
  // CATEGORY FILTERING
  // ============================================================

  /// Set the selected category filter
  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  /// Load distinct categories from current reports
  Future<void> loadReportCategories() async {
    try {
      _reportCategories = await ReportsService.getReportCategories();
      debugPrint('ReportsProvider: Loaded ${_reportCategories.length} report categories');
      notifyListeners();
    } catch (e) {
      debugPrint('ReportsProvider: Error loading report categories: $e');
    }
  }

  // ============================================================
  // REPORTS LOADING
  // ============================================================

  /// Load all reports (live and saved)
  Future<void> loadReports() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get watchlist categories for filtering
      final watchlistCategories = enabledWatchlist
          .map((w) => w.category.toLowerCase())
          .toSet()
          .toList();

      // Load live and saved reports in parallel
      final results = await Future.wait([
        ReportsService.getLiveReports(categories: watchlistCategories),
        ReportsService.getSavedReports(),
        ReportsService.getReportCategories(),
      ]);

      // Deduplicate reports by ID
      final liveList = results[0] as List<Report>;
      final seenIds = <String>{};
      _liveReports = liveList.where((r) {
        if (seenIds.contains(r.id)) return false;
        seenIds.add(r.id);
        return true;
      }).toList();

      _savedReports = results[1] as List<Report>;
      _reportCategories = results[2] as List<String>;

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
    // Skip if announcements are disabled
    if (!announcementsEnabled) return;

    // Skip if no schedule is active
    if (!shouldAnnounceNow()) return;

    try {
      // Get watchlist categories
      final watchlistCategories = enabledWatchlist
          .map((w) => w.category.toLowerCase())
          .toList();

      // Get active announcement categories from schedules
      final activeCategories = getActiveAnnouncementCategories();

      // Filter to categories that are both in watchlist and have active schedules
      List<String>? filterCategories;
      if (activeCategories.isNotEmpty && !activeCategories.contains('all')) {
        filterCategories = watchlistCategories
            .where((c) => activeCategories.contains(c))
            .toList();

        // If no overlap, skip
        if (filterCategories.isEmpty) return;
      } else {
        filterCategories = watchlistCategories;
      }

      // Get unannounced reports
      final unannounced = await ReportsService.getUnannounced(
        categories: filterCategories,
      );

      if (unannounced.isNotEmpty) {
        debugPrint('ReportsProvider: Found ${unannounced.length} unannounced report(s)');

        // Queue all unannounced reports
        _pendingReportQueue = unannounced;

        // Take the most recent one for immediate announcement
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
      _announcedReportIds.add(reportId);
      _lastAnnouncedReport = _pendingAnnouncement;
      _pendingAnnouncement = null;

      // Remove from queue
      _pendingReportQueue.removeWhere((r) => r.id == reportId);

      notifyListeners();
    }
  }

  /// Get the next report from the queue
  Report? getNextQueuedReport() {
    if (_pendingReportQueue.isEmpty) return null;

    // Skip already announced
    _pendingReportQueue.removeWhere((r) => _announcedReportIds.contains(r.id));

    if (_pendingReportQueue.isEmpty) return null;

    final next = _pendingReportQueue.first;
    _pendingAnnouncement = next;
    notifyListeners();
    return next;
  }

  /// Clear the report queue
  void clearReportQueue() {
    _pendingReportQueue.clear();
    _pendingAnnouncement = null;
    notifyListeners();
  }

  // ============================================================
  // REPORT ACTIONS
  // ============================================================

  /// Get a single report by ID
  Future<Report?> getReport(String reportId) async {
    return await ReportsService.getReport(reportId);
  }

  /// Check if a report is saved
  bool isReportSaved(String reportId) {
    return _savedReportIds.contains(reportId);
  }

  /// Check if a report is announced
  bool isReportAnnounced(String reportId) {
    return _announcedReportIds.contains(reportId);
  }

  /// Save a report
  Future<bool> saveReport(String reportId) async {
    final success = await ReportsService.saveReport(reportId);
    if (success) {
      _savedReportIds.add(reportId);

      // Move from live to saved in local state
      final reportIndex = _liveReports.indexWhere((r) => r.id == reportId);
      if (reportIndex != -1) {
        final report = _liveReports[reportIndex];
        _liveReports.removeAt(reportIndex);
        _savedReports.insert(0, report);
        onReportsListChanged?.call();
      }

      notifyListeners();
    }
    return success;
  }

  /// Unsave a report
  Future<bool> unsaveReport(String reportId) async {
    final success = await ReportsService.unsaveReport(reportId);
    if (success) {
      _savedReportIds.remove(reportId);

      // Move from saved to live in local state
      final reportIndex = _savedReports.indexWhere((r) => r.id == reportId);
      if (reportIndex != -1) {
        final report = _savedReports[reportIndex];
        _savedReports.removeAt(reportIndex);

        // Only add to live if not expired
        if (!report.isExpired) {
          _liveReports.insert(0, report);
        }

        onReportsListChanged?.call();
      }

      notifyListeners();
    }
    return success;
  }

  /// Delete a report (removes from user's saved list, not global)
  Future<bool> deleteReport(String reportId) async {
    // For users, "delete" means unsave
    final success = await unsaveReport(reportId);
    if (success) {
      // Also remove from live reports view
      _liveReports.removeWhere((r) => r.id == reportId);
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
      debugPrint('ReportsProvider: Loaded ${_watchlist.length} watchlist items');
      notifyListeners();
    } catch (e) {
      debugPrint('ReportsProvider: Error loading watchlist: $e');
    }
  }

  /// Load available categories from news_sources
  Future<void> loadAvailableCategories() async {
    try {
      _availableCategories = await ReportsService.getAvailableCategories();
      debugPrint('ReportsProvider: Loaded ${_availableCategories.length} available categories');
      notifyListeners();
    } catch (e) {
      debugPrint('ReportsProvider: Error loading categories: $e');
    }
  }

  /// Add a category/subcategory to the watchlist
  Future<bool> addToWatchlist({
    required String category,
    String? subcategory,
  }) async {
    if (category.trim().isEmpty) return false;

    final success = await ReportsService.addToWatchlist(
      category: category,
      subcategory: subcategory,
    );
    if (success) {
      await loadWatchlist(); // Reload to get the new item with ID
    }
    return success;
  }

  /// Remove a category/subcategory from the watchlist
  Future<bool> removeFromWatchlist({
    required String category,
    String? subcategory,
  }) async {
    final success = await ReportsService.removeFromWatchlist(
      category: category,
      subcategory: subcategory,
    );
    if (success) {
      _watchlist.removeWhere(
        (w) => w.category == category.toLowerCase() &&
            w.subcategory == subcategory?.toLowerCase(),
      );
      notifyListeners();
    }
    return success;
  }

  /// Toggle enabled state of a watchlist item
  Future<bool> toggleWatchlistItem(String itemId, bool enabled) async {
    final success = await ReportsService.toggleWatchlistItem(itemId, enabled);
    if (success) {
      final index = _watchlist.indexWhere((w) => w.id == itemId);
      if (index != -1) {
        _watchlist[index] = _watchlist[index].copyWith(enabled: enabled);
        notifyListeners();
      }
    }
    return success;
  }

  /// Check if a category/subcategory is in the watchlist
  bool isInWatchlist(String category, String? subcategory) {
    return _watchlist.any(
      (w) => w.category == category.toLowerCase() &&
          w.subcategory == subcategory?.toLowerCase() &&
          w.enabled,
    );
  }

  /// Get grouped categories (main categories with their subcategories)
  /// Uses LinkedHashMap to preserve insertion order
  Map<String, List<NewsCategory>> get groupedCategories {
    final grouped = LinkedHashMap<String, List<NewsCategory>>();
    for (final cat in _availableCategories) {
      grouped.putIfAbsent(cat.category, () => []).add(cat);
    }
    return grouped;
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
