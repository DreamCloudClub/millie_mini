import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
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

  ReminderProvider({
    required OpenAIService openaiService,
    required StorageService storageService,
  })  : _openaiService = openaiService,
        _storageService = storageService;

  List<Reminder> get reminders => _reminders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Get reminders that are not completed (future reminders)
  List<Reminder> get activeReminders => _reminders
      .where((r) => !r.isCompleted)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Get past reminders (triggered within last 24 hours, sorted by lastTriggeredAt descending)
  List<Reminder> getPastReminders() {
    final now = DateTime.now();
    final oneDayAgo = now.subtract(const Duration(days: 1));

    return _reminders
        .where((r) =>
            r.lastTriggeredAt != null && r.lastTriggeredAt!.isAfter(oneDayAgo))
        .toList()
      ..sort((a, b) {
        // Sort by lastTriggeredAt descending (most recent first)
        final aTime = a.lastTriggeredAt!;
        final bTime = b.lastTriggeredAt!;
        return bTime.compareTo(aTime);
      });
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('ReminderProvider init - loading from local storage');

      // Load reminders from local storage
      await loadReminders();

      // Trigger a one-time check to reschedule any recurring reminders that are in the past
      await _reschedulePastRecurringReminders();
    } catch (e) {
      debugPrint('Reminder init error: $e');
      _error = 'Failed to load reminders';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load reminders from local storage
  Future<void> loadReminders({bool reset = true}) async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('Loading reminders from local storage');

      // Load from local storage
      final storedData = await _storageService.getString('reminders');
      if (storedData != null && storedData.isNotEmpty) {
        final List<dynamic> decoded =
            (await compute(_parseReminders, storedData)) as List<dynamic>;
        final loadedReminders = <Reminder>[];

        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));

        for (final data in decoded) {
          try {
            final reminder = Reminder.fromJson(data as Map<String, dynamic>);
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
              loadedReminders.add(reminder);
              debugPrint(
                  'Loaded reminder: ${reminder.id} - ${reminder.title} (scheduled: ${reminder.scheduledAt}, recurring: $isRecurring)');
            }
          } catch (e) {
            debugPrint('Error parsing reminder: $e');
          }
        }

        if (reset) {
          _reminders = loadedReminders;
        } else {
          _reminders.addAll(loadedReminders);
        }

        debugPrint('Successfully loaded ${_reminders.length} reminders');

        // Schedule all reminders for notifications
        if (reset) {
          try {
            final notificationService =
                ReminderNotificationService.getInstance();
            if (notificationService.isInitialized) {
              await notificationService.scheduleAllReminders(_reminders);
            }
          } catch (e) {
            debugPrint('Error scheduling all reminders: $e');
          }
        }
      } else {
        debugPrint('No reminders found in local storage');
        if (reset) {
          _reminders = [];
        }
      }

      _error = null;
    } catch (e, stackTrace) {
      debugPrint('Error loading reminders: $e');
      debugPrint('Stack trace: $stackTrace');
      _error = 'Failed to load reminders: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  static List<dynamic> _parseReminders(String data) {
    // Import dart:convert for JSON parsing in isolate
    return (const JsonDecoder()).convert(data) as List<dynamic>;
  }

  /// Save reminders to local storage
  Future<void> _saveReminders() async {
    try {
      final data = _reminders.map((r) => r.toJson()).toList();
      await _storageService.saveString(
          'reminders', const JsonEncoder().convert(data));
      debugPrint('Saved ${_reminders.length} reminders to local storage');
    } catch (e) {
      debugPrint('Error saving reminders: $e');
    }
  }

  /// Reschedule any recurring reminders that are scheduled for past dates
  Future<void> _reschedulePastRecurringReminders() async {
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

      debugPrint(
          'Found ${remindersToUpdate.length} recurring reminders scheduled for past dates, rescheduling...');

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

          // Update local copy
          final index = _reminders.indexWhere((r) => r.id == reminder.id);
          if (index != -1) {
            _reminders[index] = reminder.copyWith(
              scheduledAt: newScheduledDate,
              eventTime: reminder.eventTime != null
                  ? newScheduledDate.add(
                      reminder.eventTime!.difference(reminder.scheduledAt))
                  : null,
            );
          }

          debugPrint(
              'Rescheduled reminder ${reminder.id} from ${reminder.scheduledAt} to $newScheduledDate');
        } catch (e) {
          debugPrint('Error rescheduling reminder ${reminder.id}: $e');
        }
      }

      if (remindersToUpdate.isNotEmpty) {
        await _saveReminders();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in _reschedulePastRecurringReminders: $e');
    }
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
        timeString =
            '$hours hour${hours > 1 ? 's' : ''} and $minutes minute${minutes > 1 ? 's' : ''}';
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
  Future<String?> _saveReminderTTSFile(
      String reminderId, String audioPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final remindersDir = Directory('${appDir.path}/reminders');

      if (!await remindersDir.exists()) {
        await remindersDir.create(recursive: true);
      }

      final sourceFile = File(audioPath);
      final destPath = '${remindersDir.path}/reminder_$reminderId.mp3';

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
    String? voice,
  }) async {
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
        debugPrint(
            'Error generating TTS for reminder (continuing anyway): $e');
      }

      // Add notes to metadata if provided
      if (notes != null && notes.isNotEmpty) {
        metadata ??= {};
        metadata['notes'] = notes;
      }

      final reminder = Reminder(
        id: reminderId,
        userId: 'local_user',
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

      // Add to local list
      _reminders.add(reminder);
      _reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      // Save to local storage
      await _saveReminders();

      // Schedule notification for this reminder
      try {
        final notificationService = ReminderNotificationService.getInstance();
        if (notificationService.isInitialized) {
          await notificationService.scheduleReminderNotification(reminder);
        }
      } catch (e) {
        debugPrint('Error scheduling notification for new reminder: $e');
      }

      _error = null;
      _isLoading = false;
      notifyListeners();

      return reminder;
    } catch (e, stackTrace) {
      debugPrint('ERROR creating reminder: $e');
      debugPrint('Stack trace: $stackTrace');
      _error = 'Failed to create reminder: ${e.toString()}';
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

      // Handle notes - merge with existing metadata
      final existingMetadata =
          Map<String, dynamic>.from(existing.metadata ?? {});
      if (notes != null) {
        existingMetadata['notes'] = notes;
      }
      if (metadata != null) {
        existingMetadata.addAll(metadata);
      }

      // Update local copy
      final updated = existing.copyWith(
        title: title,
        scheduledAt: scheduledAt,
        eventTime: eventTime,
        advanceNoticeMinutes: advanceNoticeMinutes,
        recurrence: recurrence,
        completedAt: completedAt,
        reminderSent: reminderSent,
        metadata: existingMetadata.isNotEmpty ? existingMetadata : null,
        updatedAt: DateTime.now(),
      );

      _reminders[index] = updated;
      _reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      // Save to local storage
      await _saveReminders();

      // Update scheduled notification
      try {
        final notificationService = ReminderNotificationService.getInstance();
        if (notificationService.isInitialized) {
          // Cancel existing notification
          await notificationService.cancelScheduledNotification(reminderId);
          // Schedule new notification if reminder is still active and in the future
          if (!updated.isCompleted &&
              !updated.reminderSent &&
              updated.scheduledAt.isAfter(DateTime.now())) {
            await notificationService.scheduleReminderNotification(updated);
          }
        }
      } catch (e) {
        debugPrint('Error updating scheduled notification: $e');
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
      }

      // Remove from local list
      _reminders.removeWhere((r) => r.id == reminderId);

      // Save to local storage
      await _saveReminders();

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

// JSON decoder/encoder for isolate usage
class JsonDecoder {
  const JsonDecoder();
  dynamic convert(String input) {
    return _parseJson(input);
  }

  static dynamic _parseJson(String input) {
    // Use dart:convert which is available in isolates
    return (input.isEmpty) ? [] : _jsonDecode(input);
  }

  static dynamic _jsonDecode(String source) {
    // Simple JSON parsing - delegates to the actual implementation
    int i = 0;

    void skipWhitespace() {
      while (i < source.length &&
          (source[i] == ' ' ||
              source[i] == '\n' ||
              source[i] == '\r' ||
              source[i] == '\t')) {
        i++;
      }
    }

    String parseString() {
      i++; // skip opening '"'
      final buffer = StringBuffer();
      while (i < source.length && source[i] != '"') {
        if (source[i] == '\\' && i + 1 < source.length) {
          i++;
          switch (source[i]) {
            case 'n':
              buffer.write('\n');
              break;
            case 'r':
              buffer.write('\r');
              break;
            case 't':
              buffer.write('\t');
              break;
            case '\\':
              buffer.write('\\');
              break;
            case '"':
              buffer.write('"');
              break;
            case 'u':
              if (i + 4 < source.length) {
                final hex = source.substring(i + 1, i + 5);
                buffer.writeCharCode(int.parse(hex, radix: 16));
                i += 4;
              }
              break;
            default:
              buffer.write(source[i]);
          }
        } else {
          buffer.write(source[i]);
        }
        i++;
      }
      i++; // skip closing '"'
      return buffer.toString();
    }

    bool parseBool() {
      if (source.substring(i).startsWith('true')) {
        i += 4;
        return true;
      }
      i += 5;
      return false;
    }

    dynamic parseNull() {
      i += 4;
      return null;
    }

    num parseNumber() {
      final start = i;
      if (source[i] == '-') i++;
      while (i < source.length &&
          (source[i].codeUnitAt(0) >= 48 && source[i].codeUnitAt(0) <= 57)) {
        i++;
      }
      if (i < source.length && source[i] == '.') {
        i++;
        while (i < source.length &&
            (source[i].codeUnitAt(0) >= 48 && source[i].codeUnitAt(0) <= 57)) {
          i++;
        }
      }
      if (i < source.length && (source[i] == 'e' || source[i] == 'E')) {
        i++;
        if (i < source.length && (source[i] == '+' || source[i] == '-')) i++;
        while (i < source.length &&
            (source[i].codeUnitAt(0) >= 48 && source[i].codeUnitAt(0) <= 57)) {
          i++;
        }
      }
      final str = source.substring(start, i);
      return str.contains('.') ? double.parse(str) : int.parse(str);
    }

    // Forward declarations for mutually recursive functions
    late dynamic Function() parseValue;
    late Map<String, dynamic> Function() parseObject;
    late List<dynamic> Function() parseArray;

    parseObject = () {
      final result = <String, dynamic>{};
      i++; // skip '{'
      skipWhitespace();
      if (i < source.length && source[i] == '}') {
        i++;
        return result;
      }
      while (i < source.length) {
        skipWhitespace();
        final key = parseString();
        skipWhitespace();
        i++; // skip ':'
        skipWhitespace();
        result[key] = parseValue();
        skipWhitespace();
        if (i >= source.length || source[i] == '}') {
          i++;
          break;
        }
        i++; // skip ','
      }
      return result;
    };

    parseArray = () {
      final result = <dynamic>[];
      i++; // skip '['
      skipWhitespace();
      if (i < source.length && source[i] == ']') {
        i++;
        return result;
      }
      while (i < source.length) {
        skipWhitespace();
        result.add(parseValue());
        skipWhitespace();
        if (i >= source.length || source[i] == ']') {
          i++;
          break;
        }
        i++; // skip ','
      }
      return result;
    };

    parseValue = () {
      skipWhitespace();
      if (i >= source.length) return null;
      final c = source[i];
      if (c == '{') return parseObject();
      if (c == '[') return parseArray();
      if (c == '"') return parseString();
      if (c == 't' || c == 'f') return parseBool();
      if (c == 'n') return parseNull();
      return parseNumber();
    };

    return parseValue();
  }
}

class JsonEncoder {
  const JsonEncoder();
  String convert(dynamic value) {
    return _encode(value);
  }

  static String _encode(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is String) return '"${_escapeString(value)}"';
    if (value is List) {
      return '[${value.map(_encode).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries
          .map((e) => '"${_escapeString(e.key.toString())}":${_encode(e.value)}')
          .join(',');
      return '{$entries}';
    }
    return '"$value"';
  }

  static String _escapeString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
