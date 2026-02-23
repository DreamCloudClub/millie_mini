/// Frequency options for report announcements
enum AnnouncementFrequency {
  minutes15(15, 'Every 15 min'),
  minutes30(30, 'Every 30 min'),
  hour1(60, 'Every hour'),
  hour2(120, 'Every 2 hours'),
  hour3(180, 'Every 3 hours'),
  hour6(360, 'Every 6 hours'),
  hour12(720, 'Every 12 hours'),
  hour24(1440, 'Daily');

  final int minutes;
  final String displayName;

  const AnnouncementFrequency(this.minutes, this.displayName);

  /// Get frequency from minutes value
  static AnnouncementFrequency fromMinutes(int minutes) {
    return AnnouncementFrequency.values.firstWhere(
      (f) => f.minutes == minutes,
      orElse: () => AnnouncementFrequency.minutes30,
    );
  }
}

/// Time-based announcement schedule for a category
/// Stored in Supabase (syncs across devices)
class CategorySchedule {
  final String id;
  final String userId;
  final List<String> categories;  // List of categories (empty = all from watchlist)
  final int startTimeMinutes;     // Minutes from midnight (540 = 9:00 AM)
  final int endTimeMinutes;       // Minutes from midnight (840 = 2:00 PM)
  final List<int> daysOfWeek;     // [1,2,3,4,5] = Mon-Fri (1=Monday, 7=Sunday)
  final int frequencyMinutes;     // How often to trigger during this window
  final bool enabled;
  final DateTime createdAt;

  CategorySchedule({
    required this.id,
    required this.userId,
    required this.categories,
    required this.startTimeMinutes,
    required this.endTimeMinutes,
    required this.daysOfWeek,
    required this.frequencyMinutes,
    required this.enabled,
    required this.createdAt,
  });

  /// Create a new schedule with defaults
  factory CategorySchedule.create({
    required String userId,
    List<String>? categories,
    int startTimeMinutes = 540,  // 9:00 AM
    int endTimeMinutes = 1260,   // 9:00 PM
    List<int>? daysOfWeek,
    int frequencyMinutes = 30,
    bool enabled = true,
  }) {
    return CategorySchedule(
      id: '',  // Will be assigned by Supabase
      userId: userId,
      categories: categories ?? [],  // Empty = all categories
      startTimeMinutes: startTimeMinutes,
      endTimeMinutes: endTimeMinutes,
      daysOfWeek: daysOfWeek ?? [1, 2, 3, 4, 5, 6, 7],
      frequencyMinutes: frequencyMinutes,
      enabled: enabled,
      createdAt: DateTime.now(),
    );
  }

  /// Create from Supabase JSON
  factory CategorySchedule.fromJson(Map<String, dynamic> json) {
    List<int> days = [1, 2, 3, 4, 5];
    if (json['days_of_week'] != null) {
      final daysJson = json['days_of_week'];
      if (daysJson is List) {
        days = daysJson.map((e) => e as int).toList();
      }
    }

    // Handle categories - can be stored as array or legacy single category
    List<String> categories = [];
    if (json['categories'] != null) {
      final catsJson = json['categories'];
      if (catsJson is List) {
        categories = catsJson.map((e) => e as String).toList();
      }
    } else if (json['category'] != null) {
      // Legacy single category support
      final cat = json['category'] as String;
      if (cat != 'all') {
        categories = [cat];
      }
    }

    return CategorySchedule(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      categories: categories,
      startTimeMinutes: json['start_time'] as int,
      endTimeMinutes: json['end_time'] as int,
      daysOfWeek: days,
      frequencyMinutes: json['frequency'] as int? ?? 30,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'categories': categories,
      'start_time': startTimeMinutes,
      'end_time': endTimeMinutes,
      'days_of_week': daysOfWeek,
      'frequency': frequencyMinutes,
      'enabled': enabled,
    };
  }

  /// Convert to JSON for Supabase update
  Map<String, dynamic> toUpdateJson() {
    return {
      'categories': categories,
      'start_time': startTimeMinutes,
      'end_time': endTimeMinutes,
      'days_of_week': daysOfWeek,
      'frequency': frequencyMinutes,
      'enabled': enabled,
    };
  }

  /// Create a copy with updated fields
  CategorySchedule copyWith({
    List<String>? categories,
    int? startTimeMinutes,
    int? endTimeMinutes,
    List<int>? daysOfWeek,
    int? frequencyMinutes,
    bool? enabled,
  }) {
    return CategorySchedule(
      id: id,
      userId: userId,
      categories: categories ?? this.categories,
      startTimeMinutes: startTimeMinutes ?? this.startTimeMinutes,
      endTimeMinutes: endTimeMinutes ?? this.endTimeMinutes,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      frequencyMinutes: frequencyMinutes ?? this.frequencyMinutes,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
    );
  }

  /// Check if the schedule is active right now
  bool isActiveNow() {
    if (!enabled) return false;

    final now = DateTime.now();

    // Check day of week (DateTime uses 1=Monday, 7=Sunday - same as our format)
    if (!daysOfWeek.contains(now.weekday)) return false;

    // Check time window
    final currentMinutes = now.hour * 60 + now.minute;

    // Handle overnight schedules (end < start means crosses midnight)
    if (endTimeMinutes < startTimeMinutes) {
      return currentMinutes >= startTimeMinutes || currentMinutes < endTimeMinutes;
    }

    // Normal daytime schedule
    return currentMinutes >= startTimeMinutes && currentMinutes < endTimeMinutes;
  }

  /// Get frequency as enum
  AnnouncementFrequency get frequency => AnnouncementFrequency.fromMinutes(frequencyMinutes);

  /// Format time range for display
  String get timeRangeDisplay {
    return '${_formatTime(startTimeMinutes)} - ${_formatTime(endTimeMinutes)}';
  }

  String _formatTime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    final period = hours >= 12 ? 'PM' : 'AM';
    final displayHour = hours > 12 ? hours - 12 : (hours == 0 ? 12 : hours);

    if (mins == 0) {
      return '$displayHour $period';
    } else {
      return '$displayHour:${mins.toString().padLeft(2, '0')} $period';
    }
  }

  /// Get display label for days of week
  String get daysDisplay {
    if (daysOfWeek.length == 7) return 'Every day';
    if (_listEquals(daysOfWeek, [1, 2, 3, 4, 5])) return 'Weekdays';
    if (_listEquals(daysOfWeek, [6, 7])) return 'Weekends';

    const dayNames = ['', 'M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'];
    return daysOfWeek.map((d) => dayNames[d]).join(', ');
  }

  /// Get display label for categories
  String get categoryDisplay {
    if (categories.isEmpty) return 'All categories';
    if (categories.length == 1) {
      return _capitalize(categories.first);
    }
    return categories.map(_capitalize).join(', ');
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sortedA = List<int>.from(a)..sort();
    final sortedB = List<int>.from(b)..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}
