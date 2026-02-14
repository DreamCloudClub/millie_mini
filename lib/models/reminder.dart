import 'package:flutter/foundation.dart';

enum ReminderRecurrence {
  none,
  daily,
  weekly,
  monthly,
}

extension ReminderRecurrenceExtension on ReminderRecurrence {
  String get displayName {
    switch (this) {
      case ReminderRecurrence.none:
        return 'None';
      case ReminderRecurrence.daily:
        return 'Daily';
      case ReminderRecurrence.weekly:
        return 'Weekly';
      case ReminderRecurrence.monthly:
        return 'Monthly';
    }
  }

  String get value {
    switch (this) {
      case ReminderRecurrence.none:
        return 'none';
      case ReminderRecurrence.daily:
        return 'daily';
      case ReminderRecurrence.weekly:
        return 'weekly';
      case ReminderRecurrence.monthly:
        return 'monthly';
    }
  }

  static ReminderRecurrence fromString(String value) {
    switch (value) {
      case 'daily':
        return ReminderRecurrence.daily;
      case 'weekly':
        return ReminderRecurrence.weekly;
      case 'monthly':
        return ReminderRecurrence.monthly;
      default:
        return ReminderRecurrence.none;
    }
  }
}

@immutable
class Reminder {
  final String id;
  final String userId;
  final String title;
  final DateTime scheduledAt; // When to trigger the reminder (may be before actual event time)
  final DateTime? eventTime; // Optional: Actual event time (if different from scheduledAt)
  final int? advanceNoticeMinutes; // Optional: Minutes before event to remind (e.g., 60 for 1 hour)
  final ReminderRecurrence recurrence;
  final DateTime? recurrenceEndDate;
  final DateTime? completedAt;
  final bool reminderSent;
  final DateTime? lastTriggeredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  const Reminder({
    required this.id,
    required this.userId,
    required this.title,
    required this.scheduledAt,
    this.eventTime,
    this.advanceNoticeMinutes,
    this.recurrence = ReminderRecurrence.none,
    this.recurrenceEndDate,
    this.completedAt,
    this.reminderSent = false,
    this.lastTriggeredAt,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  bool get isCompleted => completedAt != null;
  bool get isOverdue => !isCompleted && scheduledAt.isBefore(DateTime.now());
  bool get isDueToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduledDate = DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day);
    return scheduledDate == today;
  }
  bool get isDueTomorrow {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final scheduledDate = DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day);
    return scheduledDate == tomorrow;
  }

  /// Get the actual event time (or scheduledAt if eventTime not set)
  DateTime get actualEventTime => eventTime ?? scheduledAt;
  
  /// Get formatted reminder text including advance notice if applicable
  String get reminderText {
    if (advanceNoticeMinutes != null && eventTime != null) {
      final hours = advanceNoticeMinutes! ~/ 60;
      final minutes = advanceNoticeMinutes! % 60;
      String timeString;
      if (hours > 0 && minutes > 0) {
        timeString = '$hours hour${hours > 1 ? 's' : ''} and $minutes minute${minutes > 1 ? 's' : ''}';
      } else if (hours > 0) {
        timeString = '$hours hour${hours > 1 ? 's' : ''}';
      } else {
        timeString = '$minutes minute${minutes > 1 ? 's' : ''}';
      }
      return '$title (in $timeString)';
    }
    return title;
  }

  Reminder copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? scheduledAt,
    DateTime? eventTime,
    int? advanceNoticeMinutes,
    ReminderRecurrence? recurrence,
    DateTime? recurrenceEndDate,
    DateTime? completedAt,
    bool? reminderSent,
    DateTime? lastTriggeredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Reminder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      eventTime: eventTime ?? this.eventTime,
      advanceNoticeMinutes: advanceNoticeMinutes ?? this.advanceNoticeMinutes,
      recurrence: recurrence ?? this.recurrence,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      completedAt: completedAt ?? this.completedAt,
      reminderSent: reminderSent ?? this.reminderSent,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    // Convert to UTC before sending to Supabase (TIMESTAMPTZ expects UTC)
    // If scheduledAt is local, convert to UTC; if already UTC, use as-is
    final scheduledAtUtc = scheduledAt.isUtc ? scheduledAt : scheduledAt.toUtc();
    final createdAtUtc = createdAt.isUtc ? createdAt : createdAt.toUtc();
    final updatedAtUtc = updatedAt.isUtc ? updatedAt : updatedAt.toUtc();
    
    debugPrint('Reminder.toJson: Converting to UTC for Supabase:');
    debugPrint('  - scheduledAt (local): $scheduledAt (isUtc: ${scheduledAt.isUtc})');
    debugPrint('  - scheduledAt (UTC): $scheduledAtUtc');
    debugPrint('  - scheduledAt ISO string: ${scheduledAtUtc.toIso8601String()}');
    
    final json = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'title': title,
      'scheduled_at': scheduledAtUtc.toIso8601String(),
      'recurrence': recurrence.value,
      'reminder_sent': reminderSent,
      'created_at': createdAtUtc.toIso8601String(),
      'updated_at': updatedAtUtc.toIso8601String(),
    };
    
    // Only include optional fields if they have values
    if (eventTime != null) {
      final eventTimeUtc = eventTime!.isUtc ? eventTime! : eventTime!.toUtc();
      json['event_time'] = eventTimeUtc.toIso8601String();
    }
    if (advanceNoticeMinutes != null) {
      json['advance_notice_minutes'] = advanceNoticeMinutes;
    }
    if (recurrenceEndDate != null) {
      final recurrenceEndDateUtc = recurrenceEndDate!.isUtc ? recurrenceEndDate! : recurrenceEndDate!.toUtc();
      json['recurrence_end_date'] = recurrenceEndDateUtc.toIso8601String();
    }
    if (completedAt != null) {
      final completedAtUtc = completedAt!.isUtc ? completedAt! : completedAt!.toUtc();
      json['completed_at'] = completedAtUtc.toIso8601String();
    }
    if (lastTriggeredAt != null) {
      final lastTriggeredAtUtc = lastTriggeredAt!.isUtc ? lastTriggeredAt! : lastTriggeredAt!.toUtc();
      json['last_triggered_at'] = lastTriggeredAtUtc.toIso8601String();
    }
    if (metadata != null && metadata!.isNotEmpty) {
      json['metadata'] = metadata;
    }
    
    return json;
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    // Parse timestamps from Supabase (TIMESTAMPTZ is stored in UTC)
    // DateTime.parse() will correctly handle ISO8601 with 'Z' suffix as UTC
    // If no timezone info, we assume it's already in the correct timezone
    DateTime parseTimestamp(String timestampStr) {
      debugPrint('Reminder.fromJson: Parsing timestamp string: "$timestampStr"');
      final parsed = DateTime.parse(timestampStr);
      debugPrint('Reminder.fromJson: Parsed DateTime: $parsed (isUtc: ${parsed.isUtc}, timeZoneName: ${parsed.timeZoneName})');
      // If the string ends with 'Z' or has timezone info, parsed.isUtc will be true
      // Otherwise, assume it's local time (Supabase TIMESTAMPTZ should always have timezone)
      // Convert UTC to local time for display
      final localParsed = parsed.isUtc ? parsed.toLocal() : parsed;
      debugPrint('Reminder.fromJson: Converted to local: $localParsed (timeZoneName: ${localParsed.timeZoneName})');
      return localParsed;
    }
    
    return Reminder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      scheduledAt: parseTimestamp(json['scheduled_at'] as String),
      eventTime: json['event_time'] != null
          ? parseTimestamp(json['event_time'] as String)
          : null,
      advanceNoticeMinutes: json['advance_notice_minutes'] as int?,
      recurrence: ReminderRecurrenceExtension.fromString(
        json['recurrence'] as String? ?? 'none',
      ),
      recurrenceEndDate: json['recurrence_end_date'] != null
          ? DateTime.parse(json['recurrence_end_date'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? parseTimestamp(json['completed_at'] as String)
          : null,
      reminderSent: json['reminder_sent'] as bool? ?? false,
      lastTriggeredAt: json['last_triggered_at'] != null
          ? parseTimestamp(json['last_triggered_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

