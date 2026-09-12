import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// How the AI should confirm the user's response
enum ConfirmationType {
  /// No confirmation - just move on (for final statements, greetings)
  none,
  /// Quick echo: "Got it, John Smith." then advance
  implicit,
  /// Ask for confirmation: "January 15th at 2pm, is that correct?"
  explicit,
  /// Ask for spelling confirmation: "John Smith. Does that spelling look correct?"
  explicitSpelling,
  /// AI decides based on response complexity and slot type
  auto,
}

/// Type hint for the slot - helps AI know how to handle confirmation
enum SlotType {
  /// Simple value: number, yes/no, short answer
  simple,
  /// Person's name - AI extracts and verifies spelling
  name,
  /// Date/time - AI extracts and verifies
  datetime,
  /// Address - AI extracts and verifies
  address,
  /// Phone number - AI extracts digits, displayed as a formatted number
  phone,
  /// Open-ended response that may need follow-up
  freeform,
  /// No response expected (statement only)
  none,
}

@immutable
class ConversationStep {
  final String id;
  final int order;
  final String prompt; // The scripted question to ask
  final String? slotName; // Field name for captured response (null = no response expected)
  final SlotType slotType; // Hint for how to handle the response
  final ConfirmationType confirmationType; // How to confirm the response

  const ConversationStep({
    required this.id,
    required this.order,
    required this.prompt,
    this.slotName,
    this.slotType = SlotType.simple,
    this.confirmationType = ConfirmationType.auto,
  });

  /// Whether this step captures a response
  bool get capturesResponse => slotName != null && slotType != SlotType.none;

  /// Whether AI should potentially ask follow-up based on slot type
  bool get mayNeedFollowUp => slotType == SlotType.freeform;

  /// Whether this step is collecting a phone number.
  ///
  /// Covers the explicit [SlotType.phone] as well as steps that merely ask for
  /// a phone number in their wording - AI-generated and hand-written steps
  /// often leave the slot type as simple, and those should still be read back
  /// as a formatted phone number rather than a run of digits.
  bool get collectsPhoneNumber {
    if (slotType == SlotType.phone) return true;
    if (!capturesResponse) return false;
    final text = '${slotName ?? ''} $prompt'.toLowerCase();
    return text.contains('phone') ||
        text.contains('cell number') ||
        text.contains('mobile number');
  }

  ConversationStep copyWith({
    String? id,
    int? order,
    String? prompt,
    String? slotName,
    bool clearSlotName = false,
    SlotType? slotType,
    ConfirmationType? confirmationType,
  }) {
    return ConversationStep(
      id: id ?? this.id,
      order: order ?? this.order,
      prompt: prompt ?? this.prompt,
      slotName: clearSlotName ? null : (slotName ?? this.slotName),
      slotType: slotType ?? this.slotType,
      confirmationType: confirmationType ?? this.confirmationType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order': order,
      'prompt': prompt,
      'slotName': slotName,
      'slotType': slotType.name,
      'confirmationType': confirmationType.name,
    };
  }

  factory ConversationStep.fromJson(Map<String, dynamic> json) {
    return ConversationStep(
      id: json['id'] as String,
      order: json['order'] as int,
      prompt: json['prompt'] as String? ?? json['script'] as String, // backward compat
      slotName: json['slotName'] as String? ?? json['responseKey'] as String?, // backward compat
      slotType: SlotType.values.firstWhere(
        (e) => e.name == json['slotType'],
        orElse: () => json['responseKey'] != null ? SlotType.simple : SlotType.none,
      ),
      confirmationType: ConfirmationType.values.firstWhere(
        (e) => e.name == json['confirmationType'],
        orElse: () => ConfirmationType.auto,
      ),
    );
  }

  factory ConversationStep.create({
    required int order,
    required String prompt,
    String? slotName,
    SlotType slotType = SlotType.simple,
    ConfirmationType confirmationType = ConfirmationType.auto,
  }) {
    return ConversationStep(
      id: const Uuid().v4(),
      order: order,
      prompt: prompt,
      slotName: slotName,
      slotType: slotType,
      confirmationType: confirmationType,
    );
  }
}

@immutable
class ConversationTemplate {
  final String id;
  final String name;
  final String? description;
  final List<ConversationStep> steps;
  final String? closingMessage; // Custom closing message (e.g., "A staff member will be with you shortly")
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationTemplate({
    required this.id,
    required this.name,
    this.description,
    required this.steps,
    this.closingMessage,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Default closing message if none is set
  static const String defaultClosingMessage = 'Thank you! A staff member will be with you shortly.';

  /// Get the closing message to use (custom or default)
  String get effectiveClosingMessage => closingMessage ?? defaultClosingMessage;

  ConversationTemplate copyWith({
    String? id,
    String? name,
    String? description,
    bool clearDescription = false,
    List<ConversationStep>? steps,
    String? closingMessage,
    bool clearClosingMessage = false,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ConversationTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      steps: steps ?? this.steps,
      closingMessage: clearClosingMessage ? null : (closingMessage ?? this.closingMessage),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'steps': steps.map((s) => s.toJson()).toList(),
      'closingMessage': closingMessage,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ConversationTemplate.fromJson(Map<String, dynamic> json) {
    return ConversationTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      steps: (json['steps'] as List<dynamic>)
          .map((s) => ConversationStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      closingMessage: json['closingMessage'] as String?,
      isActive: json['isActive'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  factory ConversationTemplate.create({
    required String name,
    String? description,
    String? closingMessage,
  }) {
    final now = DateTime.now();
    return ConversationTemplate(
      id: const Uuid().v4(),
      name: name,
      description: description,
      steps: [],
      closingMessage: closingMessage,
      isActive: false,
      createdAt: now,
      updatedAt: now,
    );
  }
}
