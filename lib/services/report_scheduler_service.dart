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
      // Get active schedules (time-based only, no category filtering)
      final activeSchedules = await ReportSettingsService.getActiveSchedules();
      if (activeSchedules.isEmpty) {
        return;
      }

      // Check if any schedule should trigger based on frequency
      final now = DateTime.now();
      bool shouldAnnounce = false;
      int minFrequency = 30; // Default frequency

      for (final schedule in activeSchedules) {
        final lastTime = _lastAnnouncementTimes['default'];

        // Check if enough time has passed since last announcement
        if (lastTime != null) {
          final minutesSinceLast = now.difference(lastTime).inMinutes;
          if (minutesSinceLast < schedule.frequencyMinutes) {
            continue; // Not time yet for this schedule
          }
        }

        // This schedule should trigger
        shouldAnnounce = true;
        minFrequency = schedule.frequencyMinutes;
        break; // One active schedule is enough
      }

      if (!shouldAnnounce) {
        return;
      }

      // Get enabled watchlist categories (user's preferences from settings)
      final watchlistCategories = await ReportsService.getEnabledWatchlistCategories();
      if (watchlistCategories.isEmpty) {
        return;
      }

      // Get unannounced reports from user's watchlist
      final unannounced = await ReportsService.getUnannounced(
        categories: watchlistCategories,
      );

      if (unannounced.isEmpty) {
        return;
      }

      debugPrint('ReportSchedulerService: Found ${unannounced.length} unannounced reports, triggering check-in');

      // Update last announcement time
      _lastAnnouncementTimes['default'] = now;

      // Try to start announcement (just asks if user has time)
      await _tryStartAnnouncement();
    } catch (e) {
      debugPrint('ReportSchedulerService: Error checking schedules: $e');
    }
  }

  /// Try to start a check-in (if voice is available)
  Future<void> _tryStartAnnouncement() async {
    if (_voiceProvider == null) {
      return;
    }

    // Only announce when user is in conversation (past launch button)
    if (!_isInConversation) {
      debugPrint('ReportSchedulerService: Not in conversation, skipping check-in');
      return;
    }

    // Don't interrupt if a report is currently being read
    if (_voiceProvider!.isReadingReport) {
      debugPrint('ReportSchedulerService: Report is being read, skipping check-in');
      return;
    }

    // Check if voice is in a state that allows announcements
    final state = _voiceProvider!.state;
    if (state != VoiceState.paused && state != VoiceState.sleep) {
      debugPrint('ReportSchedulerService: Voice busy (state=$state), skipping check-in');
      return;
    }

    debugPrint('ReportSchedulerService: Triggering report check-in');

    _isSessionActive = true;

    // Trigger the simple check-in question through VoiceProvider
    // Pass a dummy report - the actual report selection happens on the Reports page
    final now = DateTime.now();
    final dummyReport = Report(
      id: '',
      category: '',
      title: '',
      summary: '',
      content: '',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 48)),
    );
    _reportsProvider?.onAnnounceReport?.call(dummyReport);
  }

  /// Called when voice transitions to paused state
  void checkPendingOnPause() {
    // No longer needed - check-in is one-time per schedule trigger
  }

  /// Called when an announcement is complete
  void onAnnouncementComplete() {
    _isSessionActive = false;
  }

  /// Clear the pending state
  void clearQueue() {
    _pendingQueue.clear();
    _isSessionActive = false;
  }

  /// Get number of pending reports (deprecated, kept for compatibility)
  int get pendingCount => _pendingQueue.length;

  /// Whether there are pending announcements
  bool get hasPending => _pendingQueue.isNotEmpty;
}
