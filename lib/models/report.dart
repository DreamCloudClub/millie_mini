/// Represents an AI-generated report from Bubble's research
class Report {
  final String id;
  final String userId;
  final String title;
  final String summary;        // Brief teaser for announcement
  final String content;        // Full report for "tell me more"
  final String category;       // e.g., "technology", "weather"
  final DateTime createdAt;
  final DateTime expiresAt;    // createdAt + 48hrs
  final DateTime? announcedAt; // null = not yet announced
  final DateTime? savedAt;     // null = live, set = saved

  Report({
    required this.id,
    required this.userId,
    required this.title,
    required this.summary,
    required this.content,
    required this.category,
    required this.createdAt,
    required this.expiresAt,
    this.announcedAt,
    this.savedAt,
  });

  /// Create a new report for insertion (Supabase will generate UUID)
  factory Report.create({
    required String userId,
    required String title,
    required String summary,
    required String content,
    String category = 'general',
    Duration expiresIn = const Duration(hours: 48),
  }) {
    final now = DateTime.now();
    return Report(
      id: '', // Supabase will generate UUID
      userId: userId,
      title: title,
      summary: summary,
      content: content,
      category: category,
      createdAt: now,
      expiresAt: now.add(expiresIn),
      announcedAt: null,
      savedAt: null,
    );
  }

  /// Create from Supabase JSON
  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      announcedAt: json['announced_at'] != null
          ? DateTime.parse(json['announced_at'] as String)
          : null,
      savedAt: json['saved_at'] != null
          ? DateTime.parse(json['saved_at'] as String)
          : null,
    );
  }

  /// Convert to JSON for Supabase insert (excludes id, let Supabase generate it)
  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'title': title,
      'summary': summary,
      'content': content,
      'category': category,
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  /// Convert to JSON for Supabase update
  Map<String, dynamic> toUpdateJson() {
    return {
      'title': title,
      'summary': summary,
      'content': content,
      'category': category,
    };
  }

  /// Create a copy with updated fields
  Report copyWith({
    String? title,
    String? summary,
    String? content,
    String? category,
    DateTime? announcedAt,
    DateTime? savedAt,
  }) {
    return Report(
      id: id,
      userId: userId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      category: category ?? this.category,
      createdAt: createdAt,
      expiresAt: expiresAt,
      announcedAt: announcedAt ?? this.announcedAt,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  /// Whether this report is saved (won't auto-delete)
  bool get isSaved => savedAt != null;

  /// Whether this report has been announced to the user
  bool get isAnnounced => announcedAt != null;

  /// Whether this report has expired (only relevant for unsaved reports)
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Time until expiration
  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());

  /// Get icon name for category
  String get categoryIcon {
    switch (category.toLowerCase()) {
      case 'technology':
      case 'tech':
        return 'computer';
      case 'weather':
        return 'cloud';
      case 'sports':
        return 'sports_soccer';
      case 'business':
      case 'finance':
        return 'trending_up';
      case 'entertainment':
        return 'movie';
      case 'science':
        return 'science';
      case 'health':
        return 'health_and_safety';
      case 'politics':
        return 'account_balance';
      default:
        return 'article';
    }
  }
}
