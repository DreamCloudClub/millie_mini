import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../providers/voice_provider.dart';
import '../providers/reminder_provider.dart';
import 'reminder_notification_service.dart';

/// Singleton service that polls for due reminders and triggers alerts
class ReminderSchedulerService {
  static ReminderSchedulerService? _instance;
  
  Timer? _pollTimer;
  Timer? _midnightTimer;
  bool _isRunning = false;
  VoiceProvider? _voiceProvider;
  ReminderProvider? _reminderProvider; // Reference to ReminderProvider for refreshing lists
  Function(Reminder)? _onReminderDueNotification;
  DateTime? _lastMidnightCheck;
  List<Reminder> _pendingVoiceAlerts = []; // Queue for voice alerts during active conversations
  bool _isOnFacePage = false; // Track if we're on the face page
  
  // Private constructor for singleton
  ReminderSchedulerService._internal();
  
  factory ReminderSchedulerService.getInstance() {
    _instance ??= ReminderSchedulerService._internal();
    return _instance!;
  }
  
  bool get isRunning => _isRunning;
  
  /// Set VoiceProvider reference (call this from app initialization)
  void setVoiceProvider(VoiceProvider voiceProvider) {
    _voiceProvider = voiceProvider;
  }
  
  /// Set ReminderProvider reference (call this from app initialization)
  void setReminderProvider(ReminderProvider reminderProvider) {
    _reminderProvider = reminderProvider;
  }
  
  /// Set whether we're on the face page (call this when navigating to/from face page)
  void setOnFacePage(bool isOnFacePage) {
    _isOnFacePage = isOnFacePage;
    debugPrint('ReminderSchedulerService: isOnFacePage = $isOnFacePage');
  }
  
  /// Check for pending voice alerts when transitioning to paused state
  /// Call this from VoiceProvider when state changes to paused
  Future<void> checkPendingAlertsOnPause() async {
    if (_pendingVoiceAlerts.isEmpty) return;
    
    debugPrint('ReminderSchedulerService: Checking ${_pendingVoiceAlerts.length} pending voice alerts on pause');
    
    // Process the first pending alert (most recent)
    final reminder = _pendingVoiceAlerts.removeAt(0);
    
    // Check if still within 10-minute window
    final now = DateTime.now();
    final timeSinceScheduled = now.difference(reminder.scheduledAt);
    if (timeSinceScheduled.inMinutes > 10) {
      debugPrint('ReminderSchedulerService: Pending alert is too old (${timeSinceScheduled.inMinutes} minutes), skipping');
      // Mark as sent to prevent it from triggering again
      await _markReminderSent(reminder);
      
      // Check for more pending alerts
      if (_pendingVoiceAlerts.isNotEmpty) {
        await checkPendingAlertsOnPause();
      }
      return;
    }
    
    // Trigger the voice alert
    if (_voiceProvider != null) {
      final success = await _voiceProvider!.triggerReminderFromAlert(reminder);
      if (success) {
        debugPrint('ReminderSchedulerService: Pending voice alert triggered on pause');
        await _markReminderSent(reminder);
      }
    }
    
    // Check for more pending alerts
    if (_pendingVoiceAlerts.isNotEmpty) {
      await checkPendingAlertsOnPause();
    }
  }
  
  /// Start the scheduler
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
    
    // Clean up old reminders on launch (mark as sent to prevent old alerts)
    _cleanupOldRemindersOnLaunch();
    
    // Poll immediately, then every 30 seconds
    _checkDueReminders();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDueReminders();
    });
    
    // Check for midnight to update recurring reminders
    _scheduleMidnightCheck();
    _updateRecurringRemindersForToday();
  }
  
  /// Clean up old reminders on app launch - mark as sent to prevent old alerts from triggering
  Future<void> _cleanupOldRemindersOnLaunch() async {
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) return;
      
      final now = DateTime.now();
      final tenMinutesAgo = now.subtract(const Duration(minutes: 10));
      final tenMinutesAgoUtc = tenMinutesAgo.isUtc ? tenMinutesAgo : tenMinutesAgo.toUtc();
      final nowUtc = now.isUtc ? now : now.toUtc();
      
      // Find reminders that are due but older than 10 minutes and not yet sent
      final response = await SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .lte('scheduled_at', tenMinutesAgoUtc.toIso8601String())
          .eq('reminder_sent', false)
          .filter('completed_at', 'is', null);
      
      if (response != null && (response as List).isNotEmpty) {
        debugPrint('ReminderSchedulerService: Cleaning up ${response.length} old reminder(s) on launch');
        
        for (final row in response) {
          try {
            final reminder = Reminder.fromJson(row);
            
            // For recurring reminders, reschedule to next occurrence
            if (reminder.recurrence != ReminderRecurrence.none) {
              // Calculate next occurrence (same logic as _markReminderSent)
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
                  continue;
              }
              
              final nextScheduledDateUtc = nextScheduledDate.isUtc ? nextScheduledDate : nextScheduledDate.toUtc();
              
              // Only set last_triggered_at if it's not already set (preserve actual trigger time)
              // Use the scheduled_at time as the trigger time since we missed it
              final triggerTime = reminder.lastTriggeredAt ?? reminder.scheduledAt;
              final triggerTimeUtc = triggerTime.isUtc ? triggerTime : triggerTime.toUtc();
              
              await SupabaseConfig.client
                  .from('reminders')
                  .update({
                    'scheduled_at': nextScheduledDateUtc.toIso8601String(),
                    'reminder_sent': false,
                    'last_triggered_at': triggerTimeUtc.toIso8601String(), // Use original trigger time, not current time
                    'updated_at': nowUtc.toIso8601String(),
                  })
                  .eq('id', reminder.id);
            } else {
              // For one-time reminders, mark as sent and set last_triggered_at
              // Only set last_triggered_at if it's not already set (preserve actual trigger time)
              // Use the scheduled_at time as the trigger time since we missed it
              final triggerTime = reminder.lastTriggeredAt ?? reminder.scheduledAt;
              final triggerTimeUtc = triggerTime.isUtc ? triggerTime : triggerTime.toUtc();
              
              await SupabaseConfig.client
                  .from('reminders')
                  .update({
                    'reminder_sent': true,
                    'last_triggered_at': triggerTimeUtc.toIso8601String(), // Use original trigger time, not current time
                    'updated_at': nowUtc.toIso8601String(),
                  })
                  .eq('id', reminder.id);
            }
          } catch (e) {
            debugPrint('ReminderSchedulerService: Error cleaning up old reminder: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error in _cleanupOldRemindersOnLaunch: $e');
    }
  }
  
  /// Stop the scheduler
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
  
  /// Schedule a check for midnight to update recurring reminders
  void _scheduleMidnightCheck() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final durationUntilMidnight = tomorrow.difference(now);
    
    _midnightTimer?.cancel();
    _midnightTimer = Timer(durationUntilMidnight, () {
      _updateRecurringRemindersForToday();
      // Schedule next midnight check
      _scheduleMidnightCheck();
    });
    
    debugPrint('ReminderSchedulerService: Scheduled midnight check in ${durationUntilMidnight.inHours} hours');
  }
  
  /// Daily midnight update: Refresh all recurring reminders
  /// - Daily reminders: Reset to today (always show "Today")
  /// - Weekly/Monthly reminders: If scheduled date is in the past, reschedule to next occurrence
  /// - One-time alerts older than 24h are automatically filtered out when loading
  Future<void> _updateRecurringRemindersForToday() async {
    if (!_isRunning) return;
    
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) return;
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Check if we already ran this today
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
      
      debugPrint('ReminderSchedulerService: Running daily midnight update for reminders');
      
      // First: Mark one-time reminders with scheduled_at before today as completed (clears them from the list)
      // A reminder set at 10pm today will be removed at midnight
      // Convert local date to UTC for comparison with Supabase TIMESTAMPTZ
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayStartUtc = todayStart.toUtc();
      final oneTimeResponse = await SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .filter('completed_at', 'is', null)
          .eq('recurrence', 'none')
          .lt('scheduled_at', todayStartUtc.toIso8601String());
      
      if (oneTimeResponse != null && (oneTimeResponse as List).isNotEmpty) {
        debugPrint('ReminderSchedulerService: Marking ${oneTimeResponse.length} one-time reminders from before today as completed');
        // Convert to UTC before sending to Supabase
        final nowUtc = now.isUtc ? now : now.toUtc();
        for (final row in oneTimeResponse) {
          try {
            await SupabaseConfig.client
                .from('reminders')
                .update({
                  'completed_at': nowUtc.toIso8601String(),
                  'updated_at': nowUtc.toIso8601String(),
                })
                .eq('id', row['id']);
            debugPrint('ReminderSchedulerService: Marked one-time reminder ${row['id']} as completed (scheduled before today)');
          } catch (e) {
            debugPrint('ReminderSchedulerService: Error marking one-time reminder as completed: $e');
          }
        }
      }
      
      // Second: Update recurring reminders
      final response = await SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .filter('completed_at', 'is', null)
          .neq('recurrence', 'none');
      
      if (response != null && (response as List).isNotEmpty) {
        for (final row in response) {
          try {
            final reminder = Reminder.fromJson(row);
            final scheduledDate = DateTime(
              reminder.scheduledAt.year,
              reminder.scheduledAt.month,
              reminder.scheduledAt.day,
            );
            
            final currentScheduledTime = reminder.scheduledAt;
            DateTime? newScheduledAt;
            
            switch (reminder.recurrence) {
              case ReminderRecurrence.daily:
                // Daily reminders: Always set to today (same time)
                // This ensures they always show as "Today"
                newScheduledAt = DateTime(
                  today.year,
                  today.month,
                  today.day,
                  currentScheduledTime.hour,
                  currentScheduledTime.minute,
                );
                break;
                
              case ReminderRecurrence.weekly:
                // Weekly reminders: If scheduled date is in the past, reschedule to next occurrence (7 days from today)
                // Otherwise, keep the scheduled date (it's today or in the future)
                if (scheduledDate.isBefore(today)) {
                  // Past date - reschedule to next week
                  newScheduledAt = DateTime(
                    today.year,
                    today.month,
                    today.day,
                    currentScheduledTime.hour,
                    currentScheduledTime.minute,
                  ).add(const Duration(days: 7));
                }
                // If scheduledDate >= today, keep it as-is (don't update)
                break;
                
              case ReminderRecurrence.monthly:
                // Monthly reminders: If scheduled date is in the past, reschedule to next occurrence (1 month from today)
                // Otherwise, keep the scheduled date (it's today or in the future)
                if (scheduledDate.isBefore(today)) {
                  // Past date - reschedule to next month
                  newScheduledAt = DateTime(
                    today.year,
                    today.month + 1,
                    today.day,
                    currentScheduledTime.hour,
                    currentScheduledTime.minute,
                  );
                }
                // If scheduledDate >= today, keep it as-is (don't update)
                break;
                
              case ReminderRecurrence.none:
                // Shouldn't be in this list, but skip just in case
                continue;
            }
            
            // Only update if we calculated a new scheduled date
            // Recurring alerts are always indefinite (no end date)
            if (newScheduledAt != null) {
              // Convert to UTC before sending to Supabase
              final nowUtc = now.isUtc ? now : now.toUtc();
              final newScheduledAtUtc = newScheduledAt.isUtc ? newScheduledAt : newScheduledAt.toUtc();
              
              final updateData = <String, dynamic>{
                'scheduled_at': newScheduledAtUtc.toIso8601String(),
                'reminder_sent': false, // Reset reminder_sent so it can trigger again
                'updated_at': nowUtc.toIso8601String(),
              };
              
              // Update eventTime if it exists (maintain advance notice) - convert to UTC
              if (reminder.eventTime != null) {
                final timeDifference = reminder.eventTime!.difference(reminder.scheduledAt);
                final newEventTime = newScheduledAt.add(timeDifference);
                final newEventTimeUtc = newEventTime.isUtc ? newEventTime : newEventTime.toUtc();
                updateData['event_time'] = newEventTimeUtc.toIso8601String();
              }
              
              await SupabaseConfig.client
                  .from('reminders')
                  .update(updateData)
                  .eq('id', reminder.id);
              
              debugPrint('ReminderSchedulerService: Updated ${reminder.recurrence} recurring reminder ${reminder.id} from ${scheduledDate} to ${newScheduledAt}');
            }
          } catch (e) {
            debugPrint('ReminderSchedulerService: Error updating recurring reminder: $e');
          }
        }
      }
      
      _lastMidnightCheck = now;
      debugPrint('ReminderSchedulerService: Finished daily midnight update');
      
      // Trigger a reload of reminders in ReminderProvider so the UI updates
      // This will automatically filter out old one-time alerts (24h rule)
      // Note: We'd need access to ReminderProvider here, but we can rely on
      // the app to refresh when it comes back to foreground
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error in _updateRecurringRemindersForToday: $e');
    }
  }
  
  /// Check for due reminders and trigger alerts
  Future<void> _checkDueReminders() async {
    if (!_isRunning) return;
    
    try {
      final userId = SupabaseConfig.currentUser?.id;
      if (userId == null) {
        debugPrint('ReminderSchedulerService: No user logged in');
        return;
      }
      
      // Query for due reminders that haven't been sent yet
      // Convert current time to UTC for comparison with Supabase TIMESTAMPTZ
      final now = DateTime.now();
      final nowUtc = now.isUtc ? now : now.toUtc();
      final nowUtcString = nowUtc.toIso8601String();
      
      final response = await SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .lte('scheduled_at', nowUtcString)
          .eq('reminder_sent', false)
          .filter('completed_at', 'is', null)
          .order('scheduled_at', ascending: true)
          .limit(10);
      
      if (response != null && (response as List).isNotEmpty) {
        debugPrint('ReminderSchedulerService: Found ${response.length} due reminder(s)');
        
        for (final row in response) {
          final reminder = Reminder.fromJson(row);
          
          // Only trigger if within 10-minute window (prevents old alerts from triggering)
          final timeSinceScheduled = now.difference(reminder.scheduledAt);
          if (timeSinceScheduled.inMinutes > 10) {
            debugPrint('ReminderSchedulerService: Skipping old reminder ${reminder.title} (${timeSinceScheduled.inMinutes} minutes old)');
            // Mark as sent to prevent it from triggering again
            await _markReminderSent(reminder);
            continue;
          }
          
          // Check if we should trigger face mode alert or notification
          await _handleDueReminder(reminder);
        }
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error checking due reminders: $e');
    }
  }
  
  /// Handle a due reminder - route to appropriate handler
  Future<void> _handleDueReminder(Reminder reminder) async {
    try {
      debugPrint('ReminderSchedulerService: Reminder due - ${reminder.title}');

      // Check if we're on the face page
      if (_isOnFacePage) {
        // On face page: only use voice alerts, no pop-up notifications
        if (_voiceProvider != null) {
          // Check if a game/quiz is running - queue for after game ends
          if (_voiceProvider!.isGameRunning) {
            debugPrint('ReminderSchedulerService: Game is running, queuing voice alert for after game');
            _pendingVoiceAlerts.add(reminder);
            // Don't mark as sent yet - will be marked when triggered after game
            return; // Queued, done
          }

          final state = _voiceProvider!.state;
          if (state == VoiceState.paused || state == VoiceState.sleep) {
            // Ready mode: trigger voice alert immediately
            final success = await _voiceProvider!.triggerReminderFromAlert(reminder);
            if (success) {
              debugPrint('ReminderSchedulerService: Face mode alert triggered (ready mode)');
              await _markReminderSent(reminder);
              return; // Successfully triggered, done
            }
          } else {
            // Active conversation: queue the alert for next pause
            debugPrint('ReminderSchedulerService: Active conversation detected, queuing voice alert for next pause');
            _pendingVoiceAlerts.add(reminder);
            // Don't mark as sent yet - will be marked when triggered on pause
            return; // Queued, done
          }
        }
        // If voice provider not available, skip (no pop-up on face page)
        debugPrint('ReminderSchedulerService: On face page but voice provider not available, skipping');
        return;
      } else {
        // Not on face page: use pop-up notifications
        final notificationService = ReminderNotificationService.getInstance();
        await notificationService.showReminderNotification(reminder);
        debugPrint('ReminderSchedulerService: Pop-up notification triggered (not on face page)');
        await _markReminderSent(reminder);
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error handling due reminder: $e');
    }
  }
  
  /// Mark reminder as sent and reschedule if recurring
  Future<void> _markReminderSent(Reminder reminder) async {
    try {
      final now = DateTime.now();
      
      // Check if this is a recurring reminder
      if (reminder.recurrence != ReminderRecurrence.none) {
        // Calculate next occurrence based on recurrence type
        // Daily reminders: tomorrow (will be updated to "today" at midnight)
        // Weekly/Monthly reminders: maintain their scheduled dates
        final currentScheduledTime = reminder.scheduledAt;
        final today = DateTime(now.year, now.month, now.day);
        
        DateTime nextScheduledDate;
        switch (reminder.recurrence) {
          case ReminderRecurrence.daily:
            // Next occurrence is tomorrow at the same time
            // (Will be updated to "today" at midnight via _updateRecurringRemindersForToday)
            nextScheduledDate = DateTime(
              today.year,
              today.month,
              today.day,
              currentScheduledTime.hour,
              currentScheduledTime.minute,
            ).add(const Duration(days: 1));
            break;
          case ReminderRecurrence.weekly:
            // Next occurrence is 7 days from today at the same time
            // This will show the actual date (e.g., "Monday, Dec 23")
            // At midnight, if this date is in the past, it will be rescheduled to next week
            nextScheduledDate = DateTime(
              today.year,
              today.month,
              today.day,
              currentScheduledTime.hour,
              currentScheduledTime.minute,
            ).add(const Duration(days: 7));
            break;
          case ReminderRecurrence.monthly:
            // Next occurrence is 1 month from today at the same time
            // This will show the actual date (e.g., "Jan 1")
            // At midnight, if this date is in the past, it will be rescheduled to next month
            nextScheduledDate = DateTime(
              today.year,
              today.month + 1,
              today.day,
              currentScheduledTime.hour,
              currentScheduledTime.minute,
            );
            break;
          case ReminderRecurrence.none:
            // Shouldn't happen, but handle gracefully
            return;
        }
        
        // Recurring alerts are always indefinite (no end date)
        // Always reschedule to the next occurrence
        
        // Convert to UTC before sending to Supabase
        final nowUtc = now.isUtc ? now : now.toUtc();
        final nextScheduledDateUtc = nextScheduledDate.isUtc ? nextScheduledDate : nextScheduledDate.toUtc();
        
        // Update scheduled_at to next occurrence, reset reminder_sent, set last_triggered_at, and update eventTime if it exists
        // Use the reminder's scheduledAt (when it was supposed to trigger) as last_triggered_at, not the current time
        final triggerTime = reminder.scheduledAt; // This is when the alert was scheduled to go off
        final triggerTimeUtc = triggerTime.isUtc ? triggerTime : triggerTime.toUtc();
        
        final updateData = <String, dynamic>{
          'scheduled_at': nextScheduledDateUtc.toIso8601String(),
          'reminder_sent': false, // Reset so it can trigger again
          'last_triggered_at': triggerTimeUtc.toIso8601String(), // Use scheduled time, not current time
          'updated_at': nowUtc.toIso8601String(),
        };
        
        // If there's an eventTime, update it to match (maintaining the advance notice) - convert to UTC
        if (reminder.eventTime != null) {
          final eventTime = reminder.eventTime!;
          final timeDifference = eventTime.difference(reminder.scheduledAt);
          final newEventTime = nextScheduledDate.add(timeDifference);
          final newEventTimeUtc = newEventTime.isUtc ? newEventTime : newEventTime.toUtc();
          updateData['event_time'] = newEventTimeUtc.toIso8601String();
        }
        
        await SupabaseConfig.client
            .from('reminders')
            .update(updateData)
            .eq('id', reminder.id);
        
        debugPrint('ReminderSchedulerService: Rescheduled recurring reminder ${reminder.id} to ${nextScheduledDate}');
        
        // Refresh ReminderProvider to update UI lists
        _reminderProvider?.loadReminders();
      } else {
        // Non-recurring reminder - mark as sent and set last_triggered_at
        // Use the reminder's scheduledAt (when it was supposed to trigger) as last_triggered_at, not the current time
        final triggerTime = reminder.scheduledAt; // This is when the alert was scheduled to go off
        final triggerTimeUtc = triggerTime.isUtc ? triggerTime : triggerTime.toUtc();
        final nowUtc = now.isUtc ? now : now.toUtc();
        
        await SupabaseConfig.client
            .from('reminders')
            .update({
              'reminder_sent': true,
              'last_triggered_at': triggerTimeUtc.toIso8601String(), // Use scheduled time, not current time
              'updated_at': nowUtc.toIso8601String(),
            })
            .eq('id', reminder.id);
        
        debugPrint('ReminderSchedulerService: Marked reminder ${reminder.id} as sent');
        
        // Refresh ReminderProvider to update UI lists
        _reminderProvider?.loadReminders();
      }
    } catch (e) {
      debugPrint('ReminderSchedulerService: Error marking reminder as sent: $e');
    }
  }
}

