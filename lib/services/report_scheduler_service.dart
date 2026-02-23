import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../providers/voice_provider.dart';
import '../providers/reports_provider.dart';
import 'report_settings_service.dart';
import 'reports_service.dart';

/// Service for scheduling and triggering report announcements
/// Similar to ReminderSchedulerService but for news reports
class ReportSchedulerService {
  static ReportSchedulerService? _instance;
  static ReportSchedulerService getInstance() {
    _instance ??= ReportSchedulerService._();
    return _instance!;
  }

  ReportSchedulerService._();

  Timer? _pollTimer;
  VoiceProvider? _voiceProvider;
  ReportsProvider? _reportsProvider;

  // Track last announcement time per category to respect frequency
  final Map<String, DateTime> _lastAnnouncementTimes = {};

  // Queue of pending announcements
  final List<Report> _pendingQueue = [];

  // Whether an announcement session is currently active
  bool _isSessionActive = false;

  // Whether user is in the main conversation (past the launch button)
  // Reports only announce when this is true
  bool _isInConversation = false;

  /// Set whether user is in conversation mode (past launch button)
  /// Call this when entering/exiting ConversationPage
  void setInConversation(bool value) {
    _isInConversation = value;
    debugPrint('ReportSchedulerService: isInConversation=$value');

    // If entering conversation and have pending reports, try to announce
    if (value && _pendingQueue.isNotEmpty) {
      _tryStartAnnouncement();
    }
  }

  // Polling interval (check every minute)
  static const _pollInterval = Duration(minutes: 1);

  /// Set VoiceProvider reference
  void setVoiceProvider(VoiceProvider provider) {
    _voiceProvider = provider;
    debugPrint('ReportSchedulerService: VoiceProvider set');
  }

  /// Set ReportsProvider reference
  void setReportsProvider(ReportsProvider provider) {
    _reportsProvider = provider;
    debugPrint('ReportSchedulerService: ReportsProvider set');
  }

  /// Start the scheduler
  void start() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _checkSchedules();
    });
    debugPrint('ReportSchedulerService: Started polling (first check in ${_pollInterval.inMinutes} min)');
    // Don't check immediately - wait for first timer tick
  }

  /// Stop the scheduler
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pendingQueue.clear();
    _isSessionActive = false;
    debugPrint('ReportSchedulerService: Stopped');
  }

  /// Check if any schedules should trigger
  Future<void> _checkSchedules() async {
    if (_voiceProvider == null || _reportsProvider == null) {
      return;
    }

    // Skip if announcements are disabled (no enabled schedules)
    if (!_reportsProvider!.announcementsEnabled) {
      return;
    }

    // Skip if already in a session
    if (_isSessionActive) {
      return;
    }

    try {
      // Get active schedules
      final activeSchedules = await ReportSettingsService.getActiveSchedules();
      if (activeSchedules.isEmpty) {
        return;
      }

      // Check each schedule
      final now = DateTime.now();
      final categoriesToAnnounce = <String>{};

      for (final schedule in activeSchedules) {
        // Create a unique key for this schedule based on categories
        final categoryKey = schedule.categories.isEmpty
            ? 'all'
            : schedule.categories.join(',');
        final lastTime = _lastAnnouncementTimes[categoryKey];

        // Check if enough time has passed since last announcement
        if (lastTime != null) {
          final minutesSinceLast = now.difference(lastTime).inMinutes;
          if (minutesSinceLast < schedule.frequencyMinutes) {
            continue; // Not time yet
          }
        }

        // This schedule should be checked - add its categories
        if (schedule.categories.isEmpty) {
          // Empty categories means all
          categoriesToAnnounce.add('all');
        } else {
          for (final cat in schedule.categories) {
            categoriesToAnnounce.add(cat.toLowerCase());
          }
        }
      }

      if (categoriesToAnnounce.isEmpty) {
        return;
      }

      // Get enabled watchlist categories
      final watchlistCategories = await ReportsService.getEnabledWatchlistCategories();
      if (watchlistCategories.isEmpty) {
        return;
      }

      // Filter to categories that are in both watchlist and active schedules
      List<String>? filterCategories;
      if (categoriesToAnnounce.contains('all')) {
        filterCategories = watchlistCategories;
      } else {
        filterCategories = watchlistCategories
            .where((c) => categoriesToAnnounce.contains(c))
            .toList();

        if (filterCategories.isEmpty) {
          return;
        }
      }

      // Get unannounced reports
      final unannounced = await ReportsService.getUnannounced(
        categories: filterCategories,
      );

      if (unannounced.isEmpty) {
        return;
      }

      debugPrint('ReportSchedulerService: Found ${unannounced.length} unannounced reports');

      // Queue reports for announcement
      _pendingQueue.clear();
      _pendingQueue.addAll(unannounced);

      // Try to start announcement
      await _tryStartAnnouncement();
    } catch (e) {
      debugPrint('ReportSchedulerService: Error checking schedules: $e');
    }
  }

  /// Try to start an announcement (if voice is available)
  Future<void> _tryStartAnnouncement() async {
    if (_voiceProvider == null || _pendingQueue.isEmpty) {
      return;
    }

    // Only announce when user is in conversation (past launch button)
    if (!_isInConversation) {
      debugPrint('ReportSchedulerService: Not in conversation, skipping announcement');
      return;
    }

    // Check if voice is in a state that allows announcements
    final state = _voiceProvider!.state;
    if (state != VoiceState.paused && state != VoiceState.sleep) {
      debugPrint('ReportSchedulerService: Voice busy (state=$state), will retry later');
      return;
    }

    // Start announcement session
    final report = _pendingQueue.first;
    _pendingQueue.removeAt(0);

    debugPrint('ReportSchedulerService: Starting announcement for "${report.title}"');

    _isSessionActive = true;

    // Update last announcement time for this category
    final categoryKey = '${report.category}:${report.subcategory ?? ''}';
    _lastAnnouncementTimes[categoryKey] = DateTime.now();

    // Trigger announcement through ReportsProvider
    _reportsProvider?.onAnnounceReport?.call(report);
  }

  /// Called when voice transitions to paused state
  /// Check if we have pending announcements
  void checkPendingOnPause() {
    if (_pendingQueue.isNotEmpty && !_isSessionActive) {
      debugPrint('ReportSchedulerService: Voice paused, checking pending queue');
      _tryStartAnnouncement();
    }
  }

  /// Called when an announcement is complete
  void onAnnouncementComplete() {
    _isSessionActive = false;

    // Check if there are more reports in queue
    if (_pendingQueue.isNotEmpty) {
      debugPrint('ReportSchedulerService: ${_pendingQueue.length} more reports in queue');
      // Give a brief pause before next announcement
      Future.delayed(const Duration(seconds: 2), () {
        _tryStartAnnouncement();
      });
    }
  }

  /// Clear the pending queue
  void clearQueue() {
    _pendingQueue.clear();
    _isSessionActive = false;
  }

  /// Get number of pending reports
  int get pendingCount => _pendingQueue.length;

  /// Whether there are pending announcements
  bool get hasPending => _pendingQueue.isNotEmpty;
}
