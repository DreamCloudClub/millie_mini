/// Model for a story page
class StoryPage {
  final String id;
  final String storyId;
  final String title;
  final int pageNumber;
  final String text;
  final String? imageUrl;
  final String? audioUrl;

  const StoryPage({
    required this.id,
    required this.storyId,
    required this.title,
    required this.pageNumber,
    required this.text,
    this.imageUrl,
    this.audioUrl,
  });

  factory StoryPage.fromJson(Map<String, dynamic> json) {
    return StoryPage(
      id: json['id'] as String,
      storyId: json['story_id'] as String,
      title: json['title'] as String,
      pageNumber: json['page_number'] as int,
      text: json['text'] as String,
      imageUrl: json['image_url'] as String?,
      audioUrl: json['audio_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'story_id': storyId,
      'title': title,
      'page_number': pageNumber,
      'text': text,
      'image_url': imageUrl,
      'audio_url': audioUrl,
    };
  }

  StoryPage copyWith({
    String? id,
    String? storyId,
    String? title,
    int? pageNumber,
    String? text,
    String? imageUrl,
    String? audioUrl,
  }) {
    return StoryPage(
      id: id ?? this.id,
      storyId: storyId ?? this.storyId,
      title: title ?? this.title,
      pageNumber: pageNumber ?? this.pageNumber,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      audioUrl: audioUrl ?? this.audioUrl,
    );
  }
}

/// Summary of a story (for menu display)
class StorySummary {
  final String storyId;
  final String title;
  final int pageCount;

  const StorySummary({
    required this.storyId,
    required this.title,
    required this.pageCount,
  });
}
