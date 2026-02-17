import 'package:flutter/material.dart';

enum FaceColor {
  white,
  blue,
  green,
  yellow,
  orange,
  red,
  purple,
}

extension FaceColorExtension on FaceColor {
  Color get color {
    switch (this) {
      case FaceColor.white:
        return Colors.white;
      case FaceColor.blue:
        return const Color(0xFF30C1FF);
      case FaceColor.green:
        return const Color(0xFF4CAF50);
      case FaceColor.yellow:
        return const Color(0xFFFFEB3B);
      case FaceColor.orange:
        return const Color(0xFFFF9800);
      case FaceColor.red:
        return const Color(0xFFF44336);
      case FaceColor.purple:
        return const Color(0xFF9C27B0);
    }
  }

  String get displayName {
    switch (this) {
      case FaceColor.white:
        return 'White';
      case FaceColor.blue:
        return 'Blue';
      case FaceColor.green:
        return 'Green';
      case FaceColor.yellow:
        return 'Yellow';
      case FaceColor.orange:
        return 'Orange';
      case FaceColor.red:
        return 'Red';
      case FaceColor.purple:
        return 'Purple';
    }
  }
}

enum EyeShape {
  circles,
  squares,
  roundedSquares,
}

extension EyeShapeExtension on EyeShape {
  String get displayName {
    switch (this) {
      case EyeShape.circles:
        return 'Circles';
      case EyeShape.squares:
        return 'Squares';
      case EyeShape.roundedSquares:
        return 'Rounded Squares';
    }
  }

  double get borderRadius {
    switch (this) {
      case EyeShape.circles:
        return 1000; // Large enough to be circular
      case EyeShape.squares:
        return 0;
      case EyeShape.roundedSquares:
        return 20;
    }
  }
}

@immutable
class Agent {
  final String id;
  final String name;
  final FaceColor faceColor;
  final EyeShape eyeShape;
  final String? faceImageId;
  final String aiServiceId;
  final String voice;
  final String personalityId;
  final String introMessage;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Agent({
    required this.id,
    required this.name,
    required this.faceColor,
    required this.eyeShape,
    this.faceImageId,
    required this.aiServiceId,
    required this.voice,
    required this.personalityId,
    this.introMessage = 'Hello {username}, it\'s me Millie your personal AI Agent. How can I help you?',
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if this agent uses a custom face image instead of robot face
  bool get usesFaceImage => faceImageId != null;

  Agent copyWith({
    String? id,
    String? name,
    FaceColor? faceColor,
    EyeShape? eyeShape,
    String? faceImageId,
    bool clearFaceImageId = false,
    String? aiServiceId,
    String? voice,
    String? personalityId,
    String? introMessage,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Agent(
      id: id ?? this.id,
      name: name ?? this.name,
      faceColor: faceColor ?? this.faceColor,
      eyeShape: eyeShape ?? this.eyeShape,
      faceImageId: clearFaceImageId ? null : (faceImageId ?? this.faceImageId),
      aiServiceId: aiServiceId ?? this.aiServiceId,
      voice: voice ?? this.voice,
      personalityId: personalityId ?? this.personalityId,
      introMessage: introMessage ?? this.introMessage,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'faceColor': faceColor.index,
      'eyeShape': eyeShape.index,
      'faceImageId': faceImageId,
      'aiServiceId': aiServiceId,
      'voice': voice,
      'personalityId': personalityId,
      'introMessage': introMessage,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      id: json['id'] as String,
      name: json['name'] as String,
      faceColor: FaceColor.values[json['faceColor'] as int],
      eyeShape: EyeShape.values[json['eyeShape'] as int],
      faceImageId: json['faceImageId'] as String?,
      aiServiceId: json['aiServiceId'] as String,
      voice: json['voice'] as String,
      personalityId: json['personalityId'] as String,
      introMessage: json['introMessage'] as String? ?? 'Hello {username}, it\'s me Millie your personal AI Agent. How can I help you?',
      isActive: json['isActive'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  factory Agent.defaultAgent() {
    final now = DateTime.now();
    return Agent(
      id: 'default_agent',
      name: 'Millie',
      faceColor: FaceColor.white,
      eyeShape: EyeShape.roundedSquares,
      aiServiceId: 'dream_cloud_default',
      voice: 'Alloy',
      personalityId: 'default_home',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}

