/// Represents an AI-generated report from the news automation system
/// Reports are GLOBAL - user-specific state (saved, announced) is in junction tables
class Report {
  final String id;
  final String title;
  final String summary;        // Brief teaser for announcement
  final String content;        // Full report for "tell me more"
  final String category;       // e.g., "technology", "weather"
  final String? subcategory;   // e.g., "ai", "robotics" (optional)
  final List<String> topics;   // Keywords for filtering
  final List<String> sourceArticleIds; // References to raw_articles used
  final String? audioUrl;      // Cached TTS audio URL (generated on first play)
  final DateTime createdAt;
  final DateTime expiresAt;    // createdAt + 48hrs

  Report({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.category,
    this.subcategory,
    this.topics = const [],
    this.sourceArticleIds = const [],
    this.audioUrl,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Create from Supabase JSON
  factory Report.fromJson(Map<String, dynamic> json) {
    // Parse source_article_ids from Postgres UUID array
    List<String> sourceIds = [];
    if (json['source_article_ids'] != null) {
      sourceIds = (json['source_article_ids'] as List)
          .map((e) => e.toString())
          .toList();
    }

    // Parse topics from Postgres text array
    List<String> topicsList = [];
    if (json['topics'] != null) {
      topicsList = (json['topics'] as List)
          .map((e) => e.toString())
          .toList();
    }

    return Report(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      content: json['content'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      subcategory: json['subcategory'] as String?,
      topics: topicsList,
      sourceArticleIds: sourceIds,
      audioUrl: json['audio_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert (excludes id, let Supabase generate it)
  Map<String, dynamic> toInsertJson() {
    return {
      'title': title,
      'summary': summary,
      'content': content,
      'category': category,
      'subcategory': subcategory,
      'topics': topics,
      'source_article_ids': sourceArticleIds,
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
      'subcategory': subcategory,
      'topics': topics,
    };
  }

  /// Create a copy with updated fields
  Report copyWith({
    String? title,
    String? summary,
    String? content,
    String? category,
    String? subcategory,
    List<String>? topics,
    List<String>? sourceArticleIds,
    String? audioUrl,
  }) {
    return Report(
      id: id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      topics: topics ?? this.topics,
      sourceArticleIds: sourceArticleIds ?? this.sourceArticleIds,
      audioUrl: audioUrl ?? this.audioUrl,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  /// Display label combining category and subcategory
  String get categoryLabel {
    if (subcategory != null && subcategory!.isNotEmpty) {
      return '${category.toUpperCase()} / ${subcategory!.toUpperCase()}';
    }
    return category.toUpperCase();
  }

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
