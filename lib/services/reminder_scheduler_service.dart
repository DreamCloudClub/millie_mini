import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../providers/voice_provider.dart';
import '../providers/reminder_provider.dart';
import 'reminder_notification_service.dart';

/// Singleton service that polls for due reminders and triggers alerts
/// Uses local ReminderProvider for storage instead of Supabase
class ReminderSchedulerService {
  static ReminderSchedulerService? _instance;

  Timer? _pollTimer;
  Timer? _midnightTimer;
  bool _isRunning = false;
  VoiceProvider? _voiceProvider;
  ReminderProvider? _reminderProvider;
  Function(Reminder)? _onReminderDueNotification;
  DateTime? _lastMidnightCheck;
  List<Reminder> _pendingVoiceAlerts = [];
  bool _isOnFacePage = false;

  ReminderSchedulerService._internal();

  factory ReminderSchedulerService.getInstance() {
    _instance ??= ReminderSchedulerService._internal();
    return _instance!;
  }

  bool get isRunning => _isRunning;

  void setVoiceProvider(VoiceProvider voiceProvider) {
    _voiceProvider = voiceProvider;
  }

  void setReminderProvider(ReminderProvider reminderProvider) {
    _reminderProvider = reminderProvider;
  }

  void setOnFacePage(bool isOnFacePage) {
    _isOnFacePage = isOnFacePage;
    debugPrint('ReminderSchedulerService: isOnFacePage = $isOnFacePage');
  }

  Future<void> checkPendingAlertsOnPause() async {
    if (_pendingVoiceAlerts.isEmpty) return;

    debugPrint(
        'ReminderSchedulerService: Checking ${_pendingVoiceAlerts.length} pending voice alerts on pause');

    final reminder = _pendingVoiceAlerts.removeAt(0);

    final now = DateTime.now();
    final timeSinceScheduled = now.difference(reminder.scheduledAt);
    if (timeSinceScheduled.inMinutes > 10) {
      debugPrint(
          'ReminderSchedulerService: Pending alert is too old (${timeSinceScheduled.inMinutes} minutes), skipping');
      await _markReminderSent(reminder);

      if (_pendingVoiceAlerts.isNotEmpty) {
        await checkPendingAlertsOnPause();
      }
      return;
    }

    if (_voiceProvider != null) {
      final success = await _voiceProvider!.triggerReminderFromAlert(reminder);
      if (success) {
        debugPrint(
            'ReminderSchedulerService: Pending voice alert triggered on pause');
        await _markReminderSent(reminder);
      }
    }

    if (_pendingVoiceAlerts.isNotEmpty) {
      await checkPendingAlertsOnPause();
    }
  }

  void start({
    Function(Reminder)? onReminderDueNotification,
  }) {
    if (_isRunning) {
      debugPrint('ReminderSchedulerService: Already running');
      return;
    }

    _onReminderDueNotification = onReminderDueNotification;
    _isRunning = true;

    debugPrint('ReminderSchedulerService: Starting (polling every 30 seconds)');

    _checkDueReminders();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDueReminders();
    });

    _scheduleMidnightCheck();
  }

  void stop() {
    if (!_isRunning) return;

    debugPrint('ReminderSchedulerService: Stopping');
    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _midnightTimer?.cancel();
    _midnightTimer = null;
    _voiceProvider = null;
    _onReminderDueNotification = null;
    _lastMidnightCheck = null;
  }

  void _scheduleMidnightCheck() {
    final now = DateTime.now();
    final tomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final durationUntilMidnight = tomorrow.difference(now);

    _midnightTimer?.cancel();
    _midnightTimer = Timer(durationUntilMidnight, () {
      _updateRecurringRemindersForToday();
      _scheduleMidnightCheck();
    });

    debugPrint(
        'ReminderSchedulerService: Scheduled midnight check in ${durationUntilMidnight.inHours} hours');
  }

  Future<void> _updateRecurringRemindersForToday() async {
    if (!_isRunning || _reminderProvider == null) return;

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (_lastMidnightCheck != null) {
        final lastCheckDate = DateTime(
          _lastMidnightCheck!.year,
          _lastMidnightCheck!.month,
          _lastMidnightCheck!.day,
        );
        if (lastCheckDate == today) {
          debugPrint('ReminderSchedulerService: Already updated reminders today');
          return;
        }
      }

      debugPrint(
          'ReminderSchedulerService: Running daily midnight update for reminders');

      // Reload reminders to get fresh data
      await _reminderProvider!.loadReminders();

      _lastMidnightCheck = now;
      debugPrint('ReminderSchedulerService: Finished daily midnight update');
    } catch (e) {
      debugPrint(
          'ReminderSchedulerService: Error in _updateRecurringRemindersForToday: $e');
    }
  }

  Future<void> _checkDueReminders() async {
    if (!_isRunning || _reminderProvider == null) return;

    try {
      final now = DateTime.now();

      // Get active reminders from provider
      final reminders = _reminderProvider!.activeReminders;

      // Find due reminders that haven't been sent
      final dueReminders = reminders.where((reminder) {
        return reminder.scheduledAt.isBefore(now) && !reminder.reminderSent;
      }).toList();

      if (dueReminders.isNotEmpty) {
        debugPrint(
            'ReminderSchedulerService: Found ${dueReminders.length} due reminder(s)');

        for (final reminder in dueReminders) {
          final timeSinceScheduled = now.difference(reminder.scheduledAt);
          if (timeSinceScheduled.inMinutes > 10) {
            debugPrint(
                'ReminderSchedulerService: Skipping old reminder ${reminder.title} (${timeSinceScheduled.inMinutes} minutes old)');
            await _markReminderSent(reminder);
            continue;
          }

          await _handleDueReminder(reminder);
        }
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error checking due reminders: $e');
    }
  }

  Future<void> _handleDueReminder(Reminder reminder) async {
    try {
      debugPrint('ReminderSchedulerService: Reminder due - ${reminder.title}');

      if (_isOnFacePage) {
        if (_voiceProvider != null) {
          final state = _voiceProvider!.state;
          if (state == VoiceState.paused || state == VoiceState.sleep) {
            final success =
                await _voiceProvider!.triggerReminderFromAlert(reminder);
            if (success) {
              debugPrint(
                  'ReminderSchedulerService: Face mode alert triggered (ready mode)');
              await _markReminderSent(reminder);
              return;
            }
          } else {
            debugPrint(
                'ReminderSchedulerService: Active conversation detected, queuing voice alert for next pause');
            _pendingVoiceAlerts.add(reminder);
            return;
          }
        }
        debugPrint(
            'ReminderSchedulerService: On face page but voice provider not available, skipping');
        return;
      } else {
        final notificationService = ReminderNotificationService.getInstance();
        await notificationService.showReminderNotification(reminder);
        debugPrint(
            'ReminderSchedulerService: Pop-up notification triggered (not on face page)');
        await _markReminderSent(reminder);
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error handling due reminder: $e');
    }
  }

  Future<void> _markReminderSent(Reminder reminder) async {
    if (_reminderProvider == null) return;

    try {
      final now = DateTime.now();

      if (reminder.recurrence != ReminderRecurrence.none) {
        // Calculate next occurrence based on recurrence type
        final currentScheduledTime = reminder.scheduledAt;
        final today = DateTime(now.year, now.month, now.day);

        DateTime nextScheduledDate;
        switch (reminder.recurrence) {
          case ReminderRecurrence.daily:
            nextScheduledDate = DateTime(
              today.year,
              today.month,
              today.day,
              currentScheduledTime.hour,
              currentScheduledTime.minute,
            ).add(const Duration(days: 1));
            break;
          case ReminderRecurrence.weekly:
            nextScheduledDate = DateTime(
              today.year,
              today.month,
              today.day,
              currentScheduledTime.hour,
              currentScheduledTime.minute,
            ).add(const Duration(days: 7));
            break;
          case ReminderRecurrence.monthly:
            nextScheduledDate = DateTime(
              today.year,
              today.month + 1,
              today.day,
              currentScheduledTime.hour,
              currentScheduledTime.minute,
            );
            break;
          case ReminderRecurrence.none:
            return;
        }

        // Update via ReminderProvider
        await _reminderProvider!.updateReminder(
          reminderId: reminder.id,
          scheduledAt: nextScheduledDate,
          reminderSent: false,
        );

        debugPrint(
            'ReminderSchedulerService: Rescheduled recurring reminder ${reminder.id} to $nextScheduledDate');
      } else {
        // Mark as sent
        await _reminderProvider!.updateReminder(
          reminderId: reminder.id,
          reminderSent: true,
        );

        debugPrint(
            'ReminderSchedulerService: Marked reminder ${reminder.id} as sent');
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error marking reminder as sent: $e');
    }
  }
}
