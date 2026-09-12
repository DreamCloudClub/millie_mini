import 'package:flutter/foundation.dart';

enum AIServiceType {
  openai,
}

extension AIServiceTypeExtension on AIServiceType {
  String get displayName {
    switch (this) {
      case AIServiceType.openai:
        return 'OpenAI';
    }
  }

  List<String> get availableVoices {
    switch (this) {
      case AIServiceType.openai:
        return ['Alloy', 'Echo', 'Fable', 'Onyx', 'Nova', 'Shimmer'];
    }
  }
}

enum AIServiceStatus {
  active,
  inactive,
  unknown,
}

extension AIServiceStatusExtension on AIServiceStatus {
  String get displayName {
    switch (this) {
      case AIServiceStatus.active:
        return 'Active';
      case AIServiceStatus.inactive:
        return 'Inactive';
      case AIServiceStatus.unknown:
        return 'Unknown';
    }
  }

  bool get isUsable => this == AIServiceStatus.active;
}

@immutable
class AIService {
  final String id;
  final AIServiceType type;
  final String displayName;
  final String? apiKey;
  final AIServiceStatus status;
  final bool isDreamCloud;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AIService({
    required this.id,
    required this.type,
    required this.displayName,
    this.apiKey,
    this.status = AIServiceStatus.unknown,
    this.isDreamCloud = false,
    required this.createdAt,
    required this.updatedAt,
  });

  AIService copyWith({
    String? id,
    AIServiceType? type,
    String? displayName,
    String? apiKey,
    AIServiceStatus? status,
    bool? isDreamCloud,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AIService(
      id: id ?? this.id,
      type: type ?? this.type,
      displayName: displayName ?? this.displayName,
      apiKey: apiKey ?? this.apiKey,
      status: status ?? this.status,
      isDreamCloud: isDreamCloud ?? this.isDreamCloud,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'displayName': displayName,
      'apiKey': apiKey,
      'status': status.index,
      'isDreamCloud': isDreamCloud,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AIService.fromJson(Map<String, dynamic> json) {
    return AIService(
      id: json['id'] as String,
      type: AIServiceType.values[json['type'] as int],
      displayName: json['displayName'] as String,
      apiKey: json['apiKey'] as String?,
      status: AIServiceStatus.values[json['status'] as int],
      isDreamCloud: json['isDreamCloud'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static AIService openai() {
    final now = DateTime.now();
    return AIService(
      id: 'openai_default',
      type: AIServiceType.openai,
      displayName: 'OpenAI',
      isDreamCloud: false,
      status: AIServiceStatus.active,
      createdAt: now,
      updatedAt: now,
    );
  }
}
