/// Represents a user's subscription to a news category/subcategory
class WatchlistItem {
  final String id;
  final String userId;
  final String category;       // e.g., "technology", "business"
  final String? subcategory;   // e.g., "ai", "robotics" (null = all subcategories)
  final bool enabled;
  final DateTime createdAt;

  WatchlistItem({
    required this.id,
    required this.userId,
    required this.category,
    this.subcategory,
    this.enabled = true,
    required this.createdAt,
  });

  /// Create from Supabase JSON
  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      category: json['category'] as String,
      subcategory: json['subcategory'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'category': category,
      'subcategory': subcategory,
      'enabled': enabled,
    };
  }

  /// Create a copy with updated fields
  WatchlistItem copyWith({
    String? category,
    String? subcategory,
    bool? enabled,
  }) {
    return WatchlistItem(
      id: id,
      userId: userId,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
    );
  }

  /// Display label for UI
  String get displayLabel {
    if (subcategory != null && subcategory!.isNotEmpty) {
      return '${_capitalize(category)} - ${_capitalize(subcategory!)}';
    }
    return '${_capitalize(category)} (All)';
  }

  /// Short label for chips
  String get shortLabel {
    if (subcategory != null && subcategory!.isNotEmpty) {
      return _capitalize(subcategory!);
    }
    return _capitalize(category);
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WatchlistItem &&
        other.category == category &&
        other.subcategory == subcategory;
  }

  @override
  int get hashCode => category.hashCode ^ (subcategory?.hashCode ?? 0);
}

/// Represents an available category/subcategory from news_sources
class NewsCategory {
  final String category;
  final String? subcategory;

  NewsCategory({
    required this.category,
    this.subcategory,
  });

  factory NewsCategory.fromJson(Map<String, dynamic> json) {
    return NewsCategory(
      category: json['category'] as String,
      subcategory: json['subcategory'] as String?,
    );
  }

  String get displayLabel {
    if (subcategory != null && subcategory!.isNotEmpty) {
      return '${_capitalize(category)} - ${_capitalize(subcategory!)}';
    }
    return _capitalize(category);
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NewsCategory &&
        other.category == category &&
        other.subcategory == subcategory;
  }

  @override
  int get hashCode => category.hashCode ^ (subcategory?.hashCode ?? 0);
}
