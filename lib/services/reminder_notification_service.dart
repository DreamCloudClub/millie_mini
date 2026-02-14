import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/models.dart';
import 'supabase_service.dart';

/// Service for handling reminder notifications (pre-recorded alerts when app is closed)
class ReminderNotificationService {
  static ReminderNotificationService? _instance;
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  
  ReminderNotificationService._internal();
  
  factory ReminderNotificationService.getInstance() {
    _instance ??= ReminderNotificationService._internal();
    return _instance!;
  }
  
  bool get isInitialized => _initialized;
  
  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('ReminderNotificationService: Already initialized');
      return;
    }
    
    try {
      // Initialize timezone database (required for tz.getLocation)
      tz_data.initializeTimeZones();
      debugPrint('ReminderNotificationService: Timezone database initialized');
      
      // Request notification permissions
      final status = await Permission.notification.request();
      if (status.isDenied) {
        debugPrint('ReminderNotificationService: Notification permission denied');
        // Continue anyway - some platforms don't require explicit permission
      }
      
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      // Initialization settings
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // Initialize plugin
      final initialized = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      if (initialized ?? false) {
        _initialized = true;
        debugPrint('ReminderNotificationService: Initialized successfully');
        
        // Create notification channel for Android (required for custom sounds)
        if (Platform.isAndroid) {
          await _createNotificationChannel();
        }
      } else {
        debugPrint('ReminderNotificationService: Failed to initialize');
      }
    } catch (e) {
      debugPrint('ReminderNotificationService: Error initializing: $e');
    }
  }
  
  /// Create notification channel for Android (required for custom sounds and proper behavior)
  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      'reminder_alerts', // id
      'Reminder Alerts', // name
      description: 'Notifications for reminder alerts with custom TTS audio',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: false, // Disable status bar icons/badges
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
    
    debugPrint('ReminderNotificationService: Notification channel created');
  }
  
  /// Show notification for due reminder using pre-recorded TTS
  Future<void> showReminderNotification(Reminder reminder) async {
    if (!_initialized) {
      debugPrint('ReminderNotificationService: Not initialized, skipping notification');
      return;
    }
    
    debugPrint('ReminderNotificationService: Showing notification for: ${reminder.title}');
    
    // Get TTS audio path from metadata
    final ttsPath = reminder.metadata?['tts_audio_path'] as String?;
    
    if (ttsPath == null || ttsPath.isEmpty) {
      debugPrint('ReminderNotificationService: No TTS audio path found, showing notification without sound');
      await _showNotificationWithoutSound(reminder);
      return;
    }
    
    // Check if file exists
    final file = File(ttsPath);
    if (!await file.exists()) {
      debugPrint('ReminderNotificationService: TTS file not found: $ttsPath, showing notification without sound');
      await _showNotificationWithoutSound(reminder);
      return;
    }
    
    debugPrint('ReminderNotificationService: TTS file found: $ttsPath');
    
    try {
      // For Android, we need to copy the file to a location accessible by the notification system
      // Android requires notification sounds to be in a specific location
      String? soundPath = ttsPath;
      
      if (Platform.isAndroid) {
        // Copy TTS file to a location that Android notifications can access
        soundPath = await _copySoundForAndroid(file, reminder.id);
      }
      
      // Build notification details
      // For Android, custom file sounds require content:// URI which is complex
      // For now, we'll use default notification sound (can be enhanced later)
      // iOS can use file paths directly
      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_alerts', // channelId (must match channel created above)
          'Reminder Alerts',
          channelDescription: 'Notifications for reminder alerts with custom TTS audio',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          showWhen: true,
          // Using default sound - custom file sounds require content provider setup
          // Can be enhanced later to use UriAndroidNotificationSound with proper URI
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false, // Disable badge icons
          presentSound: true,
          sound: soundPath,
        ),
      );
      
      // Show notification
      await _notifications.show(
        reminder.id.hashCode, // Use reminder ID hash as notification ID
        'Reminder',
        reminder.title,
        notificationDetails,
        payload: reminder.id, // Pass reminder ID as payload for tap handling
      );
      
      debugPrint('ReminderNotificationService: Notification shown successfully');
    } catch (e) {
      debugPrint('ReminderNotificationService: Error showing notification: $e');
      // Fallback: show notification without sound
      await _showNotificationWithoutSound(reminder);
    }
  }
  
  /// Show notification without custom sound (fallback)
  Future<void> _showNotificationWithoutSound(Reminder reminder) async {
    try {
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_alerts',
          'Reminder Alerts',
          channelDescription: 'Notifications for reminder alerts',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true, // Use default sound
          enableVibration: true,
          showWhen: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      
      await _notifications.show(
        reminder.id.hashCode,
        'Reminder',
        reminder.title,
        notificationDetails,
        payload: reminder.id,
      );
    } catch (e) {
      debugPrint('ReminderNotificationService: Error showing fallback notification: $e');
    }
  }
  
  /// Copy sound file to Android-accessible location
  /// Android requires notification sounds to be in the app's raw resources or external storage
  /// For simplicity, we'll use the file path directly if it's accessible
  Future<String?> _copySoundForAndroid(File sourceFile, String reminderId) async {
    try {
      // On Android 10+, we can't always use arbitrary file paths for notification sounds
      // We'll try to use the file directly, and if that fails, the notification will use default sound
      // The TTS files are stored in app documents directory, which should be accessible
      return sourceFile.path;
    } catch (e) {
      debugPrint('ReminderNotificationService: Error preparing sound for Android: $e');
      return null;
    }
  }
  
  /// Handle notification tap
  /// When a scheduled notification is tapped, mark the reminder as triggered
  void _onNotificationTapped(NotificationResponse response) async {
    debugPrint('ReminderNotificationService: Notification tapped: ${response.payload}');
    
    // The payload contains the reminder ID
    if (response.payload != null && response.payload!.isNotEmpty) {
      final reminderId = response.payload!;
      debugPrint('ReminderNotificationService: Marking reminder $reminderId as triggered from notification tap');
      
      // Mark the reminder as triggered in the database
      // This ensures lastTriggeredAt is set even if the app was closed when notification fired
      try {
        final now = DateTime.now();
        final nowUtc = now.isUtc ? now : now.toUtc();
        
        // Get the reminder to check if it's recurring
        final reminderResponse = await SupabaseConfig.client
            .from('reminders')
            .select()
            .eq('id', reminderId)
            .single();
        
        if (reminderResponse != null) {
          final isRecurring = reminderResponse['recurrence'] != null && 
                              reminderResponse['recurrence'] != 'none';
          
          // Use the scheduled_at time (when alert was supposed to trigger) as last_triggered_at
          final scheduledAtStr = reminderResponse['scheduled_at'] as String?;
          final triggerTime = scheduledAtStr != null 
              ? DateTime.parse(scheduledAtStr)
              : now; // Fallback to now if scheduled_at is missing
          final triggerTimeUtc = triggerTime.isUtc ? triggerTime : triggerTime.toUtc();
          
          if (isRecurring) {
            // For recurring, we need to reschedule it
            // But we'll let the scheduler handle that on next poll
            // Just mark as triggered for now
            await SupabaseConfig.client
                .from('reminders')
                .update({
                  'last_triggered_at': triggerTimeUtc.toIso8601String(), // Use scheduled time, not current time
                  'updated_at': nowUtc.toIso8601String(),
                })
                .eq('id', reminderId);
          } else {
            // For one-time, mark as sent and triggered
            await SupabaseConfig.client
                .from('reminders')
                .update({
                  'reminder_sent': true,
                  'last_triggered_at': triggerTimeUtc.toIso8601String(), // Use scheduled time, not current time
                  'updated_at': nowUtc.toIso8601String(),
                })
                .eq('id', reminderId);
          }
          
          debugPrint('ReminderNotificationService: Successfully marked reminder $reminderId as triggered');
          
          // Trigger refresh of ReminderProvider if available
          // This will be handled by the scheduler service on next poll
        }
      } catch (e) {
        debugPrint('ReminderNotificationService: Error marking reminder as triggered: $e');
      }
    }
    
    // Navigation can be handled in main.dart or app lifecycle if needed
  }
  
  /// Cancel a specific notification
  Future<void> cancelNotification(String reminderId) async {
    await _notifications.cancel(reminderId.hashCode);
  }
  
  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
  
  /// Get local timezone name (uses system timezone offset to determine IANA timezone)
  /// This maps common UTC offsets to IANA timezone names
  /// Note: TZDateTime will automatically handle DST transitions
  String _getLocalTimezoneName() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final offsetHours = offset.inHours;
    
    debugPrint('ReminderNotificationService: System timezone offset: ${offsetHours}h');
    debugPrint('ReminderNotificationService: System timezone name: ${now.timeZoneName}');
    
    // Map common timezone offsets to IANA timezone names
    // TZDateTime will handle DST automatically based on the location
    // This covers most common timezones - can be expanded as needed
    switch (offsetHours) {
      case -10: return 'Pacific/Honolulu'; // HST (no DST)
      case -9: return 'America/Anchorage'; // AKST/AKDT
      case -8: return 'America/Los_Angeles'; // PST/PDT
      case -7: return 'America/Denver'; // MST/MDT
      case -6: return 'America/Chicago'; // CST/CDT
      case -5: return 'America/New_York'; // EST/EDT
      case -4: return 'America/Halifax'; // AST/ADT
      case 0: return 'Europe/London'; // GMT/BST
      case 1: return 'Europe/Paris'; // CET/CEST
      case 2: return 'Europe/Berlin'; // CEST
      case 8: return 'Asia/Shanghai'; // CST (no DST)
      case 9: return 'Asia/Tokyo'; // JST (no DST)
      default:
        // For unknown offsets, use UTC as fallback
        // The notification will still work, but might be off by the offset amount
        // In production, you might want to log this and expand the mapping
        debugPrint('ReminderNotificationService: WARNING - Unknown timezone offset $offsetHours, using UTC fallback');
        debugPrint('ReminderNotificationService: This may cause notifications to fire at the wrong time');
        return 'UTC';
    }
  }
  
  /// Schedule a notification for a future reminder
  /// This works even when the app is closed (OS-level scheduling)
  Future<void> scheduleReminderNotification(Reminder reminder) async {
    if (!_initialized) {
      debugPrint('ReminderNotificationService: Not initialized, cannot schedule notification');
      return;
    }
    
    // Don't schedule if reminder is already sent, completed, or in the past
    if (reminder.reminderSent || reminder.isCompleted) {
      debugPrint('ReminderNotificationService: Skipping schedule - reminder already sent/completed');
      return;
    }
    
    final now = DateTime.now();
    if (reminder.scheduledAt.isBefore(now)) {
      debugPrint('ReminderNotificationService: Skipping schedule - reminder is in the past');
      return;
    }
    
    try {
      debugPrint('ReminderNotificationService: Scheduling notification for: ${reminder.title} at ${reminder.scheduledAt}');
      debugPrint('ReminderNotificationService: scheduledAt is in local time: ${reminder.scheduledAt} (timeZoneName: ${reminder.scheduledAt.timeZoneName}, isUtc: ${reminder.scheduledAt.isUtc})');
      
      // Get local timezone location based on system offset
      final localTzName = _getLocalTimezoneName();
      debugPrint('ReminderNotificationService: Detected local timezone: $localTzName');
      
      final localLocation = tz.getLocation(localTzName);
      
      // Create TZDateTime in local timezone using the reminder's local time components
      // Since reminder.scheduledAt is already in local time, we use those components directly
      final scheduledTime = tz.TZDateTime(
        localLocation,
        reminder.scheduledAt.year,
        reminder.scheduledAt.month,
        reminder.scheduledAt.day,
        reminder.scheduledAt.hour,
        reminder.scheduledAt.minute,
        reminder.scheduledAt.second,
      );
      
      debugPrint('ReminderNotificationService: Created TZDateTime: $scheduledTime (location: $localTzName)');
      
      // Get TTS audio path from metadata
      final ttsPath = reminder.metadata?['tts_audio_path'] as String?;
      
      // Build notification details
      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_alerts',
          'Reminder Alerts',
          channelDescription: 'Notifications for reminder alerts with custom TTS audio',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          showWhen: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
          sound: ttsPath, // iOS can use file paths directly
        ),
      );
      
      // Schedule the notification using zonedSchedule (works when app is closed)
      // Try exact alarm first, fall back to inexact if not permitted
      try {
        await _notifications.zonedSchedule(
          reminder.id.hashCode, // Use reminder ID hash as notification ID
          'Reminder',
          reminder.title,
          scheduledTime,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Works even in Doze mode
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: reminder.id,
          matchDateTimeComponents: reminder.recurrence != ReminderRecurrence.none
              ? _getDateTimeComponents(reminder.recurrence)
              : null, // For recurring reminders, match time components
        );
        debugPrint('ReminderNotificationService: Scheduled exact notification for ${reminder.scheduledAt}');
      } catch (exactAlarmError) {
        // Fall back to inexact alarm if exact alarms not permitted
        if (exactAlarmError.toString().contains('exact_alarms_not_permitted')) {
          debugPrint('ReminderNotificationService: Exact alarms not permitted, using inexact schedule');
          await _notifications.zonedSchedule(
            reminder.id.hashCode,
            'Reminder',
            reminder.title,
            scheduledTime,
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, // Fallback to inexact
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            payload: reminder.id,
            matchDateTimeComponents: reminder.recurrence != ReminderRecurrence.none
                ? _getDateTimeComponents(reminder.recurrence)
                : null,
          );
          debugPrint('ReminderNotificationService: Scheduled inexact notification for ${reminder.scheduledAt}');
        } else {
          rethrow; // Rethrow other errors
        }
      }
    } catch (e) {
      debugPrint('ReminderNotificationService: Error scheduling notification: $e');
    }
  }
  
  /// Get DateTimeComponents for recurring reminders
  DateTimeComponents? _getDateTimeComponents(ReminderRecurrence recurrence) {
    switch (recurrence) {
      case ReminderRecurrence.daily:
        return DateTimeComponents.time; // Match time every day
      case ReminderRecurrence.weekly:
        return DateTimeComponents.dayOfWeekAndTime; // Match day of week and time
      case ReminderRecurrence.monthly:
        return DateTimeComponents.dayOfMonthAndTime; // Match day of month and time
      case ReminderRecurrence.none:
        return null;
    }
  }
  
  /// Schedule notifications for all future reminders
  /// Call this on app startup to ensure all reminders are scheduled
  Future<void> scheduleAllReminders(List<Reminder> reminders) async {
    if (!_initialized) {
      debugPrint('ReminderNotificationService: Not initialized, cannot schedule reminders');
      return;
    }
    
    debugPrint('ReminderNotificationService: Scheduling ${reminders.length} reminders');
    
    int scheduledCount = 0;
    for (final reminder in reminders) {
      // Only schedule future, non-completed reminders
      if (!reminder.isCompleted && 
          !reminder.reminderSent && 
          reminder.scheduledAt.isAfter(DateTime.now())) {
        await scheduleReminderNotification(reminder);
        scheduledCount++;
      }
    }
    
    debugPrint('ReminderNotificationService: Scheduled $scheduledCount reminders');
  }
  
  /// Cancel scheduled notification for a reminder
  Future<void> cancelScheduledNotification(String reminderId) async {
    await _notifications.cancel(reminderId.hashCode);
    debugPrint('ReminderNotificationService: Cancelled scheduled notification for reminder $reminderId');
  }
  
  /// Get all pending scheduled notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}
