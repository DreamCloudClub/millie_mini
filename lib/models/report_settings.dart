/// User's report announcement preferences
class ReportSettings {
  final String id;
  final String userId;
  final bool enabled; // Master toggle for announcements
  final DateTime createdAt;
  final DateTime updatedAt;

  ReportSettings({
    required this.id,
    required this.userId,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Default settings for a new user
  factory ReportSettings.defaults(String userId) {
    final now = DateTime.now();
    return ReportSettings(
      id: '',
      userId: userId,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create from Supabase JSON
  factory ReportSettings.fromJson(Map<String, dynamic> json) {
    return ReportSettings(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'enabled': enabled,
    };
  }

  /// Convert to JSON for Supabase update
  Map<String, dynamic> toUpdateJson() {
    return {
      'enabled': enabled,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ReportSettings copyWith({
    bool? enabled,
  }) {
    return ReportSettings(
      id: id,
      userId: userId,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
