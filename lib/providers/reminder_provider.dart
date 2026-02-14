import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';
import '../services/reminder_notification_service.dart';

class ReminderProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  final OpenAIService _openaiService;
  final StorageService _storageService;
  
  List<Reminder> _reminders = [];
  bool _isLoading = false;
  String? _error;
  bool _hasMore = true;
  DateTime? _lastScheduledAt;
  
  ReminderProvider({
    required OpenAIService openaiService,
    required StorageService storageService,
  }) : _openaiService = openaiService,
       _storageService = storageService;
  
  List<Reminder> get reminders => _reminders;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _hasMore;
  
  /// Get reminders that are not completed (future reminders)
  List<Reminder> get activeReminders => 
      _reminders.where((r) => !r.isCompleted).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  
  /// Get past reminders (triggered within last 24 hours, sorted by lastTriggeredAt descending)
  List<Reminder> getPastReminders() {
    final now = DateTime.now();
    final oneDayAgo = now.subtract(const Duration(days: 1));
    
    return _reminders
        .where((r) => r.lastTriggeredAt != null && r.lastTriggeredAt!.isAfter(oneDayAgo))
        .toList()
      ..sort((a, b) {
        // Sort by lastTriggeredAt descending (most recent first)
        final aTime = a.lastTriggeredAt!;
        final bTime = b.lastTriggeredAt!;
        return bTime.compareTo(aTime);
      });
  }
  
  /// Always get current user ID from Supabase
  String? get _userId => SupabaseConfig.currentUser?.id;
  
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      debugPrint('ReminderProvider init - userId: $_userId');
      
      if (_userId != null) {
        // Load initial reminders from Supabase
        await loadReminders();
        
        // Trigger a one-time check to reschedule any recurring reminders that are in the past
        // This handles fresh installs where the midnight update hasn't run yet
        await _reschedulePastRecurringReminders();
      }
    } catch (e) {
      debugPrint('Reminder init error: $e');
      _error = 'Failed to load reminders';
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// Load reminders from Supabase (initial load or refresh)
  Future<void> loadReminders({bool reset = true}) async {
    if (_userId == null) {
      debugPrint('ReminderProvider: Cannot load reminders - no user ID');
      return;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      debugPrint('Loading reminders from Supabase for user: $_userId');
      
      // Load all active (non-completed) reminders
      // Strategy: Load all active reminders, then filter client-side
      // This ensures recurring reminders are always included, even if scheduled for past dates
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      // Load all non-completed reminders AND reminders with lastTriggeredAt in last 24 hours
      // We'll load all reminders for this user and filter client-side
      final response = await SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('user_id', _userId!)
          .order('scheduled_at', ascending: true)
          .limit(100); // Increased limit to handle recurring reminders
      
      debugPrint('Supabase reminders response: $response');
      debugPrint('Supabase reminders count: ${response.length}');
      
      if (response != null && (response as List).isNotEmpty) {
        debugPrint('Parsing ${response.length} reminders...');
        final loadedReminders = <Reminder>[];
        
        final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));
        
        for (final row in response) {
          try {
            final reminder = Reminder.fromJson(row);
            final isRecurring = reminder.recurrence != ReminderRecurrence.none;
            final scheduledDate = DateTime(
              reminder.scheduledAt.year,
              reminder.scheduledAt.month,
              reminder.scheduledAt.day,
            );
            
            // Check if reminder has lastTriggeredAt in last 24 hours (for past list)
            final hasRecentTrigger = reminder.lastTriggeredAt != null && 
                                     reminder.lastTriggeredAt!.isAfter(oneDayAgo);
            
            // Include reminder if:
            // 1. It's recurring (always include, even if past date)
            // 2. It's one-time and scheduled for today or future
            // 3. It has lastTriggeredAt in the last 24 hours (for past list)
            if (isRecurring || 
                scheduledDate.isAtSameMomentAs(todayStart) || 
                scheduledDate.isAfter(todayStart) ||
                hasRecentTrigger) {
              // For recurring reminders scheduled in the past, trigger a reschedule
              // (This handles fresh installs where midnight update hasn't run yet)
              if (isRecurring && scheduledDate.isBefore(todayStart)) {
                debugPrint('Recurring reminder ${reminder.id} scheduled for past date, will be rescheduled by scheduler');
              }
              
              loadedReminders.add(reminder);
              debugPrint('Loaded reminder: ${reminder.id} - ${reminder.title} (scheduled: ${reminder.scheduledAt}, recurring: $isRecurring, lastTriggered: ${reminder.lastTriggeredAt})');
            } else {
              debugPrint('Filtered out past one-time reminder: ${reminder.id} - ${reminder.title} (scheduled: ${reminder.scheduledAt})');
            }
          } catch (e) {
            debugPrint('Error parsing reminder row: $e, row: $row');
          }
        }
        
        if (reset) {
          _reminders = loadedReminders;
          _hasMore = loadedReminders.length >= 100; // Match the query limit
        } else {
          // Append for pagination
          _reminders.addAll(loadedReminders);
          _hasMore = loadedReminders.length >= 100; // Match the query limit
        }
        
        if (_reminders.isNotEmpty) {
          _lastScheduledAt = _reminders.last.scheduledAt;
        }
        
        debugPrint('Successfully loaded ${_reminders.length} reminders from Supabase');
        
        // Schedule all reminders for notifications (works when app is closed)
        if (reset) {
          try {
            final notificationService = ReminderNotificationService.getInstance();
            if (notificationService.isInitialized) {
              await notificationService.scheduleAllReminders(_reminders);
            }
          } catch (e) {
            debugPrint('Error scheduling all reminders: $e');
            // Don't fail the load if scheduling fails
          }
        }
      } else {
        debugPrint('No reminders found in Supabase (response was empty or null)');
        if (reset) {
          _reminders = [];
        }
        _hasMore = false;
      }
      
      _error = null;
    } catch (e, stackTrace) {
      debugPrint('Error loading reminders from Supabase: $e');
      debugPrint('Stack trace: $stackTrace');
      _error = 'Failed to load reminders: $e';
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// Reschedule any recurring reminders that are scheduled for past dates
  /// This ensures they show up correctly on fresh installs
  Future<void> _reschedulePastRecurringReminders() async {
    if (_userId == null) return;
    
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      // Find recurring reminders scheduled for past dates
      final remindersToUpdate = _reminders.where((r) {
        if (r.recurrence == ReminderRecurrence.none) return false;
        
        final scheduledDate = DateTime(
          r.scheduledAt.year,
          r.scheduledAt.month,
          r.scheduledAt.day,
        );
        
        return scheduledDate.isBefore(todayStart);
      }).toList();
      
      if (remindersToUpdate.isEmpty) return;
      
      debugPrint('Found ${remindersToUpdate.length} recurring reminders scheduled for past dates, rescheduling...');
      
      for (final reminder in remindersToUpdate) {
        try {
          final currentScheduledTime = reminder.scheduledAt;
          DateTime newScheduledDate;
          
          switch (reminder.recurrence) {
            case ReminderRecurrence.daily:
              // Daily: set to today at the same time
              newScheduledDate = DateTime(
                today.year,
                today.month,
                today.day,
                currentScheduledTime.hour,
                currentScheduledTime.minute,
              );
              break;
              
            case ReminderRecurrence.weekly:
              // Weekly: next week at the same time
              newScheduledDate = DateTime(
                today.year,
                today.month,
                today.day,
                currentScheduledTime.hour,
                currentScheduledTime.minute,
              ).add(const Duration(days: 7));
              break;
              
            case ReminderRecurrence.monthly:
              // Monthly: next month at the same time
              newScheduledDate = DateTime(
                today.year,
                today.month + 1,
                today.day,
                currentScheduledTime.hour,
                currentScheduledTime.minute,
              );
              break;
              
            case ReminderRecurrence.none:
              continue; // Skip non-recurring
          }
          
          // Update in Supabase - convert to UTC before sending
          final now = DateTime.now();
          final nowUtc = now.isUtc ? now : now.toUtc();
          final newScheduledDateUtc = newScheduledDate.isUtc ? newScheduledDate : newScheduledDate.toUtc();
          
          final updateData = <String, dynamic>{
            'scheduled_at': newScheduledDateUtc.toIso8601String(),
            'reminder_sent': false,
            'updated_at': nowUtc.toIso8601String(),
          };
          
          // Update eventTime if it exists - convert to UTC
          if (reminder.eventTime != null) {
            final timeDifference = reminder.eventTime!.difference(reminder.scheduledAt);
            final newEventTime = newScheduledDate.add(timeDifference);
            final newEventTimeUtc = newEventTime.isUtc ? newEventTime : newEventTime.toUtc();
            updateData['event_time'] = newEventTimeUtc.toIso8601String();
          }
          
          await SupabaseConfig.client
              .from('reminders')
              .update(updateData)
              .eq('id', reminder.id);
          
          // Update local copy
          final index = _reminders.indexWhere((r) => r.id == reminder.id);
          if (index != -1) {
            _reminders[index] = reminder.copyWith(
              scheduledAt: newScheduledDate,
              eventTime: reminder.eventTime != null 
                  ? newScheduledDate.add(reminder.eventTime!.difference(reminder.scheduledAt))
                  : null,
            );
          }
          
          debugPrint('Rescheduled reminder ${reminder.id} from ${reminder.scheduledAt} to $newScheduledDate');
        } catch (e) {
          debugPrint('Error rescheduling reminder ${reminder.id}: $e');
        }
      }
      
      if (remindersToUpdate.isNotEmpty) {
        notifyListeners(); // Notify UI of updates
      }
    } catch (e) {
      debugPrint('Error in _reschedulePastRecurringReminders: $e');
    }
  }
  
  /// Load more reminders (pagination)
  Future<void> loadMoreReminders() async {
    if (_userId == null || !_hasMore || _isLoading) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Filter to only show reminders scheduled for today or in the future
      // Convert local dates to UTC for comparison with Supabase TIMESTAMPTZ
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayStartUtc = todayStart.toUtc();
      
      var query = SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('user_id', _userId!)
          .filter('completed_at', 'is', null)
          .gte('scheduled_at', todayStartUtc.toIso8601String());
      
      if (_lastScheduledAt != null) {
        // Convert lastScheduledAt to UTC for comparison
        final lastScheduledAtUtc = _lastScheduledAt!.isUtc ? _lastScheduledAt! : _lastScheduledAt!.toUtc();
        query = query.gt('scheduled_at', lastScheduledAtUtc.toIso8601String());
      }
      
      final response = await query
          .order('scheduled_at', ascending: true)
          .limit(100); // Match the initial load limit
      
      if (response != null && (response as List).isNotEmpty) {
        // Load all reminders (already filtered by date in query)
        final loadedReminders = <Reminder>[];
        for (final row in response) {
          try {
            final reminder = Reminder.fromJson(row);
            loadedReminders.add(reminder);
          } catch (e) {
            debugPrint('Error parsing reminder row in loadMore: $e');
          }
        }
        
        _reminders.addAll(loadedReminders);
        _hasMore = loadedReminders.length >= 100; // Match the query limit
        
        if (_reminders.isNotEmpty) {
          _lastScheduledAt = _reminders.last.scheduledAt;
        }
      } else {
        _hasMore = false;
      }
      
      _error = null;
    } catch (e) {
      debugPrint('Error loading more reminders: $e');
      _error = 'Failed to load more reminders';
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// Build reminder announcement text for TTS
  String _buildReminderAnnouncementText({
    required String title,
    DateTime? eventTime,
    int? advanceNoticeMinutes,
  }) {
    if (advanceNoticeMinutes != null && eventTime != null) {
      // Advance notice format
      final hours = advanceNoticeMinutes ~/ 60;
      final minutes = advanceNoticeMinutes % 60;
      String timeString;
      if (hours > 0 && minutes > 0) {
        timeString = '$hours hour${hours > 1 ? 's' : ''} and $minutes minute${minutes > 1 ? 's' : ''}';
      } else if (hours > 0) {
        timeString = '$hours hour${hours > 1 ? 's' : ''}';
      } else {
        timeString = '$minutes minute${minutes > 1 ? 's' : ''}';
      }
      
      final eventTimeStr = DateFormat('h:mm a').format(eventTime);
      return 'Reminder: $title. This is happening in $timeString, at $eventTimeStr.';
    } else {
      // Immediate reminder
      return 'Reminder: $title.';
    }
  }
  
  /// Generate TTS audio file for reminder
  Future<String?> _generateReminderTTS({
    required String text,
    required String voice,
  }) async {
    try {
      debugPrint('Generating TTS for reminder: $text');
      
      final audioPath = await _openaiService.textToSpeech(
        text: text,
        voice: voice.toLowerCase(),
        model: 'tts-1',
      );
      
      if (audioPath != null && audioPath.isNotEmpty) {
        debugPrint('Reminder TTS generated: $audioPath');
        return audioPath;
      }
      
      debugPrint('Failed to generate reminder TTS');
      return null;
    } catch (e) {
      debugPrint('Error generating reminder TTS: $e');
      return null;
    }
  }
  
  /// Save TTS file to reminders directory and return path
  Future<String?> _saveReminderTTSFile(String reminderId, String audioPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final remindersDir = Directory('${appDir.path}/reminders');
      
      if (!await remindersDir.exists()) {
        await remindersDir.create(recursive: true);
      }
      
      final sourceFile = File(audioPath);
      final destPath = '${remindersDir.path}/reminder_$reminderId.mp3';
      final destFile = File(destPath);
      
      // Copy file to reminders directory
      await sourceFile.copy(destPath);
      
      debugPrint('Reminder TTS saved to: $destPath');
      return destPath;
    } catch (e) {
      debugPrint('Error saving reminder TTS file: $e');
      return null;
    }
  }

  /// Create a new reminder
  Future<Reminder?> createReminder({
    required String title,
    required DateTime scheduledAt,
    DateTime? eventTime,
    int? advanceNoticeMinutes,
    ReminderRecurrence recurrence = ReminderRecurrence.none,
    DateTime? recurrenceEndDate,
    String? notes,
    String? voice, // Voice to use for TTS generation (optional, defaults to agent voice)
  }) async {
    // Verify user is authenticated and user ID is available
    final currentUserId = _userId;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('ERROR: Cannot create reminder - user not authenticated (userId: $currentUserId)');
      debugPrint('Current Supabase user: ${SupabaseConfig.currentUser?.id}');
      _error = 'User not authenticated. Please log out and log back in.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
    
    debugPrint('Creating reminder for user: $currentUserId');
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final now = DateTime.now();
      final reminderId = _uuid.v4();
      
      // Build reminder announcement text
      final announcementText = _buildReminderAnnouncementText(
        title: title,
        eventTime: eventTime,
        advanceNoticeMinutes: advanceNoticeMinutes,
      );
      
      // Generate TTS audio file (use provided voice or default to 'Alloy')
      final ttsVoice = voice ?? 'Alloy';
      String? ttsAudioPath;
      Map<String, dynamic>? metadata;
      
      try {
        final generatedTTS = await _generateReminderTTS(
          text: announcementText,
          voice: ttsVoice,
        );
        
        if (generatedTTS != null) {
          // Save to reminders directory
          ttsAudioPath = await _saveReminderTTSFile(reminderId, generatedTTS);
          
          if (ttsAudioPath != null) {
            metadata = {
              'tts_audio_path': ttsAudioPath,
              'tts_text': announcementText,
              'tts_voice': ttsVoice,
            };
            debugPrint('TTS file saved for reminder: $ttsAudioPath');
          }
        }
      } catch (e) {
        debugPrint('Error generating TTS for reminder (continuing anyway): $e');
        // Continue without TTS - reminder will still work, just won't have pre-recorded audio
      }
      
      // Add notes to metadata if provided
      if (notes != null && notes.isNotEmpty) {
        metadata ??= {};
        metadata!['notes'] = notes;
      }
      
      final reminder = Reminder(
        id: reminderId,
        userId: currentUserId, // Use the validated currentUserId variable
        title: title,
        scheduledAt: scheduledAt,
        eventTime: eventTime,
        advanceNoticeMinutes: advanceNoticeMinutes,
        recurrence: recurrence,
        recurrenceEndDate: recurrenceEndDate,
        metadata: metadata,
        createdAt: now,
        updatedAt: now,
      );
      
      debugPrint('Creating new reminder: ${reminder.id} - ${reminder.title}');
      debugPrint('Reminder JSON: ${reminder.toJson()}');
      debugPrint('User ID: $_userId');
      
      // Insert to Supabase
      final reminderJson = reminder.toJson();
      debugPrint('Inserting reminder to Supabase with data: $reminderJson');
      debugPrint('User ID being used: $currentUserId');
      debugPrint('Supabase current user: ${SupabaseConfig.currentUser?.id}');
      
      dynamic response;
      try {
        response = await SupabaseConfig.client
            .from('reminders')
            .insert(reminderJson)
            .select()
            .single();
        
        debugPrint('Supabase insert response received: $response');
        debugPrint('Supabase insert response type: ${response.runtimeType}');
        
        if (response == null) {
          throw Exception('Supabase insert returned null response');
        }
      } catch (insertError, insertStack) {
        debugPrint('ERROR during Supabase insert: $insertError');
        debugPrint('Insert stack trace: $insertStack');
        debugPrint('Insert error type: ${insertError.runtimeType}');
        
        // Re-throw to be caught by outer catch block
        rethrow;
      }
      
      // Parse the response
      Reminder createdReminder;
      try {
        createdReminder = Reminder.fromJson(response);
        debugPrint('Successfully parsed reminder from Supabase response: ${createdReminder.id}');
      } catch (parseError, parseStack) {
        debugPrint('ERROR parsing Supabase response: $parseError');
        debugPrint('Parse stack trace: $parseStack');
        debugPrint('Response that failed to parse: $response');
        throw Exception('Failed to parse reminder from Supabase response: $parseError');
      }
      
      debugPrint('Successfully created reminder in Supabase: ${createdReminder.id}');
      
      // Add to local list (optimistic update)
      _reminders.add(createdReminder);
      _reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      
      // Schedule notification for this reminder (works when app is closed)
      try {
        final notificationService = ReminderNotificationService.getInstance();
        if (notificationService.isInitialized) {
          await notificationService.scheduleReminderNotification(createdReminder);
        }
      } catch (e) {
        debugPrint('Error scheduling notification for new reminder: $e');
        // Don't fail the reminder creation if scheduling fails
      }
      
      _error = null;
      _isLoading = false;
      notifyListeners();
      
      return createdReminder;
    } catch (e, stackTrace) {
      debugPrint('ERROR creating reminder: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Log more details about the error
      if (e is Exception) {
        debugPrint('Exception type: ${e.runtimeType}');
        debugPrint('Exception details: ${e.toString()}');
      }
      
      // Check if it's a Supabase error
      try {
        final errorStr = e.toString();
        if (errorStr.contains('violates row-level security') || errorStr.contains('RLS')) {
          _error = 'Permission denied: Please check your authentication';
        } else if (errorStr.contains('foreign key') || errorStr.contains('user_id')) {
          _error = 'Invalid user ID: Please log out and log back in';
        } else if (errorStr.contains('null value') || errorStr.contains('NOT NULL')) {
          _error = 'Missing required fields: Please check all fields are filled';
        } else {
          _error = 'Failed to create reminder: ${e.toString()}';
        }
      } catch (_) {
        _error = 'Failed to create reminder: ${e.toString()}';
      }
      
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }
  
  /// Update an existing reminder
  Future<bool> updateReminder({
    required String reminderId,
    String? title,
    DateTime? scheduledAt,
    DateTime? eventTime,
    int? advanceNoticeMinutes,
    ReminderRecurrence? recurrence,
    DateTime? recurrenceEndDate,
    DateTime? completedAt,
    bool? reminderSent,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    if (_userId == null) return false;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final index = _reminders.indexWhere((r) => r.id == reminderId);
      if (index == -1) {
        _error = 'Reminder not found';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final existing = _reminders[index];
      
      // Build update map - convert all DateTime values to UTC before sending to Supabase
      final now = DateTime.now();
      final nowUtc = now.isUtc ? now : now.toUtc();
      
      final updateData = <String, dynamic>{
        'updated_at': nowUtc.toIso8601String(),
      };
      
      if (title != null) updateData['title'] = title;
      if (scheduledAt != null) {
        // Convert local time to UTC before sending to Supabase
        final scheduledAtUtc = scheduledAt.isUtc ? scheduledAt : scheduledAt.toUtc();
        debugPrint('updateReminder: Converting scheduledAt to UTC: $scheduledAt (local) -> $scheduledAtUtc (UTC)');
        updateData['scheduled_at'] = scheduledAtUtc.toIso8601String();
        // Reset reminder_sent if scheduled_at changes
        updateData['reminder_sent'] = false;
      }
      if (eventTime != null) {
        final eventTimeUtc = eventTime.isUtc ? eventTime : eventTime.toUtc();
        debugPrint('updateReminder: Converting eventTime to UTC: $eventTime (local) -> $eventTimeUtc (UTC)');
        updateData['event_time'] = eventTimeUtc.toIso8601String();
      }
      if (advanceNoticeMinutes != null) updateData['advance_notice_minutes'] = advanceNoticeMinutes;
      if (recurrence != null) updateData['recurrence'] = recurrence.value;
      // Recurring alerts are always indefinite - always set to null
      updateData['recurrence_end_date'] = null;
      if (completedAt != null) {
        final completedAtUtc = completedAt.isUtc ? completedAt : completedAt.toUtc();
        updateData['completed_at'] = completedAtUtc.toIso8601String();
      } else if (completedAt == null && existing.completedAt != null) {
        // Uncompleting
        updateData['completed_at'] = null;
      }
      if (reminderSent != null) updateData['reminder_sent'] = reminderSent;
      
      // Handle notes - merge with existing metadata
      final existingMetadata = existing.metadata ?? {};
      if (notes != null) {
        existingMetadata['notes'] = notes;
      }
      if (metadata != null) {
        // Merge with existing metadata (including notes if set)
        final mergedMetadata = {...existingMetadata, ...metadata};
        updateData['metadata'] = mergedMetadata;
      } else if (notes != null) {
        // Only update metadata if notes was provided
        updateData['metadata'] = existingMetadata;
      }
      
      // Update in Supabase
      await SupabaseConfig.client
          .from('reminders')
          .update(updateData)
          .eq('id', reminderId)
          .eq('user_id', _userId!);
      
      // Get updated reminder from Supabase to ensure we have the latest data
      final updatedResponse = await SupabaseConfig.client
          .from('reminders')
          .select()
          .eq('id', reminderId)
          .single();
      
      // Update local copy
      final updated = Reminder.fromJson(updatedResponse);
      _reminders[index] = updated;
      _reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      
      // Update scheduled notification (cancel old, schedule new if needed)
      try {
        final notificationService = ReminderNotificationService.getInstance();
        if (notificationService.isInitialized) {
          // Cancel existing notification
          await notificationService.cancelScheduledNotification(reminderId);
          // Schedule new notification if reminder is still active and in the future
          if (!updated.isCompleted && !updated.reminderSent && updated.scheduledAt.isAfter(DateTime.now())) {
            await notificationService.scheduleReminderNotification(updated);
          }
        }
      } catch (e) {
        debugPrint('Error updating scheduled notification: $e');
        // Don't fail the reminder update if scheduling fails
      }
      
      _error = null;
      _isLoading = false;
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('Error updating reminder: $e');
      _error = 'Failed to update reminder';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Delete a reminder
  Future<bool> deleteReminder(String reminderId) async {
    if (_userId == null) return false;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Cancel scheduled notification
      try {
        final notificationService = ReminderNotificationService.getInstance();
        if (notificationService.isInitialized) {
          await notificationService.cancelScheduledNotification(reminderId);
        }
      } catch (e) {
        debugPrint('Error cancelling scheduled notification: $e');
        // Don't fail the deletion if cancel fails
      }
      
      // Delete from Supabase
      await SupabaseConfig.client
          .from('reminders')
          .delete()
          .eq('id', reminderId)
          .eq('user_id', _userId!);
      
      // Remove from local list
      _reminders.removeWhere((r) => r.id == reminderId);
      
      _error = null;
      _isLoading = false;
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('Error deleting reminder: $e');
      _error = 'Failed to delete reminder';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Mark reminder as completed
  Future<bool> completeReminder(String reminderId) async {
    return await updateReminder(
      reminderId: reminderId,
      completedAt: DateTime.now(),
    );
  }
  
  /// Get reminder by ID
  Reminder? getReminderById(String id) {
    try {
      return _reminders.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

