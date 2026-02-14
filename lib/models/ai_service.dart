import 'package:flutter/foundation.dart';

enum AIServiceType {
  dreamCloud,
  openai,
  gemini,
  anthropic,
}

extension AIServiceTypeExtension on AIServiceType {
  String get displayName {
    switch (this) {
      case AIServiceType.dreamCloud:
        return 'Dream Cloud AI';
      case AIServiceType.openai:
        return 'OpenAI';
      case AIServiceType.gemini:
        return 'Gemini';
      case AIServiceType.anthropic:
        return 'Anthropic';
    }
  }

  List<String> get availableVoices {
    switch (this) {
      case AIServiceType.dreamCloud:
        return ['Alloy', 'Echo', 'Fable', 'Onyx', 'Nova', 'Shimmer'];
      case AIServiceType.openai:
        return ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
      case AIServiceType.gemini:
        return ['en-US-Standard-A', 'en-US-Standard-B', 'en-US-Standard-C', 'en-US-Standard-D'];
      case AIServiceType.anthropic:
        return ['default'];
    }
  }
}

enum AIServiceStatus {
  holder,     // Crypto holder ($50+) - 500K tokens/month
  basic,      // Millie Mini Basic subscription - 500K tokens/month (~$6/month)
  pro,        // Millie Mini Pro subscription - 1M tokens/month (~$12/month)
  active,     // Legacy status (deprecated, use basic/pro)
  trial,      // Trial subscription
  inactive,
  pending,    // Awaiting payment
  expired,    // Subscription ended
  notFound,
  unknown,
}

extension AIServiceStatusExtension on AIServiceStatus {
  String get displayName {
    switch (this) {
      case AIServiceStatus.holder:
        return 'Holder';
      case AIServiceStatus.basic:
        return 'Basic';
      case AIServiceStatus.pro:
        return 'Pro';
      case AIServiceStatus.active:
        return 'Active';
      case AIServiceStatus.trial:
        return 'Trial';
      case AIServiceStatus.inactive:
        return 'Inactive';
      case AIServiceStatus.pending:
        return 'Pending';
      case AIServiceStatus.expired:
        return 'Expired';
      case AIServiceStatus.notFound:
        return 'Not Found';
      case AIServiceStatus.unknown:
        return 'Unknown';
    }
  }
  
  bool get isUsable => 
      this == AIServiceStatus.holder || 
      this == AIServiceStatus.basic ||
      this == AIServiceStatus.pro ||
      this == AIServiceStatus.active || 
      this == AIServiceStatus.trial;
}

@immutable
class AIService {
  final String id;
  final AIServiceType type;
  final String displayName;
  final String? apiKey;
  final String? subscriptionEmail;
  final AIServiceStatus status;
  final bool isDreamCloud;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AIService({
    required this.id,
    required this.type,
    required this.displayName,
    this.apiKey,
    this.subscriptionEmail,
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
    String? subscriptionEmail,
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
      subscriptionEmail: subscriptionEmail ?? this.subscriptionEmail,
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
      'subscriptionEmail': subscriptionEmail,
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
      subscriptionEmail: json['subscriptionEmail'] as String?,
      status: AIServiceStatus.values[json['status'] as int],
      isDreamCloud: json['isDreamCloud'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static AIService dreamCloud() {
    final now = DateTime.now();
    return AIService(
      id: 'dream_cloud_default',
      type: AIServiceType.dreamCloud,
      displayName: 'Dream Cloud AI',
      isDreamCloud: true,
      status: AIServiceStatus.unknown,
      createdAt: now,
      updatedAt: now,
    );
  }
}

