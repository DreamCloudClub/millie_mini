import 'package:flutter/foundation.dart';

@immutable
class FaceImage {
  final String id;
  final String name;
  final String imageUrl;
  final int displayOrder;

  const FaceImage({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.displayOrder = 0,
  });

  factory FaceImage.fromJson(Map<String, dynamic> json) {
    return FaceImage(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['image_url'] as String? ?? '',
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
      'display_order': displayOrder,
    };
  }

  FaceImage copyWith({
    String? id,
    String? name,
    String? imageUrl,
    int? displayOrder,
  }) {
    return FaceImage(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FaceImage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
