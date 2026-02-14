import 'package:flutter/foundation.dart';

@immutable
class Personality {
  final String id;
  final String name;
  final String behaviorPrompt;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Personality({
    required this.id,
    required this.name,
    required this.behaviorPrompt,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  Personality copyWith({
    String? id,
    String? name,
    String? behaviorPrompt,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Personality(
      id: id ?? this.id,
      name: name ?? this.name,
      behaviorPrompt: behaviorPrompt ?? this.behaviorPrompt,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'behaviorPrompt': behaviorPrompt,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Personality.fromJson(Map<String, dynamic> json) {
    return Personality(
      id: json['id'] as String,
      name: json['name'] as String,
      behaviorPrompt: json['behaviorPrompt'] as String,
      isDefault: json['isDefault'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  // Default personalities
  static Personality home() {
    final now = DateTime.now();
    return Personality(
      id: 'default_home',
      name: 'Home',
      behaviorPrompt: '''You are {agent_name}, a friendly and helpful AI assistant for home use. 
You are warm, supportive, and conversational. You help with everyday tasks, 
answer questions, and provide companionship. Keep responses concise and natural. 
Be encouraging and positive while remaining helpful and informative.''',
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  static Personality office() {
    final now = DateTime.now();
    return Personality(
      id: 'default_office',
      name: 'Office',
      behaviorPrompt: '''You are {agent_name}, a professional AI assistant for work environments.
You are efficient, focused, and business-oriented. You help with productivity tasks,
scheduling, information lookup, and professional communication. Keep responses brief 
and to the point. Maintain a professional tone while being helpful and supportive.''',
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}

