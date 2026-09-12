import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/conversation_template.dart';
import '../services/storage_service.dart';

class ConversationTemplateProvider extends ChangeNotifier {
  final StorageService _storage;

  List<ConversationTemplate> _templates = [];
  bool _isLoading = false;
  String? _error;

  ConversationTemplateProvider(this._storage);

  // Getters
  List<ConversationTemplate> get templates => _templates;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ConversationTemplate? get activeTemplate {
    try {
      return _templates.firstWhere((t) => t.isActive);
    } catch (_) {
      return null;
    }
  }

  // Initialize
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _storage.getString('conversation_templates');
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        _templates = decoded
            .map((d) => ConversationTemplate.fromJson(d as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading conversation templates: $e');
      _error = 'Failed to load conversation templates';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Save to storage
  Future<void> _save() async {
    final data = _templates.map((t) => t.toJson()).toList();
    await _storage.saveString('conversation_templates', jsonEncode(data));
  }

  // Create
  Future<ConversationTemplate> createTemplate({
    required String name,
    String? description,
    String? closingMessage,
  }) async {
    final template = ConversationTemplate.create(
      name: name,
      description: description,
      closingMessage: closingMessage,
    );

    _templates.add(template);
    await _save();
    notifyListeners();
    return template;
  }

  // Update
  Future<void> updateTemplate({
    required String templateId,
    String? name,
    String? description,
    bool clearDescription = false,
    String? closingMessage,
    bool clearClosingMessage = false,
    List<ConversationStep>? steps,
    bool? isActive,
  }) async {
    final index = _templates.indexWhere((t) => t.id == templateId);
    if (index == -1) return;

    // If setting this one active, deactivate others
    if (isActive == true) {
      _templates = _templates.map((t) {
        if (t.isActive && t.id != templateId) {
          return t.copyWith(isActive: false, updatedAt: DateTime.now());
        }
        return t;
      }).toList();
    }

    _templates[index] = _templates[index].copyWith(
      name: name,
      description: description,
      clearDescription: clearDescription,
      closingMessage: closingMessage,
      clearClosingMessage: clearClosingMessage,
      steps: steps,
      isActive: isActive,
      updatedAt: DateTime.now(),
    );

    await _save();
    notifyListeners();
  }

  // Delete
  Future<void> deleteTemplate(String templateId) async {
    _templates.removeWhere((t) => t.id == templateId);
    await _save();
    notifyListeners();
  }

  // Set active
  Future<void> setActiveTemplate(String templateId) async {
    _templates = _templates.map((t) {
      return t.copyWith(
        isActive: t.id == templateId,
        updatedAt: DateTime.now(),
      );
    }).toList();

    await _save();
    notifyListeners();
  }

  // Get by ID
  ConversationTemplate? getTemplateById(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  // Add step to template
  Future<void> addStep({
    required String templateId,
    required String prompt,
    String? slotName,
    SlotType slotType = SlotType.simple,
    ConfirmationType confirmationType = ConfirmationType.auto,
  }) async {
    final template = getTemplateById(templateId);
    if (template == null) return;

    final newStep = ConversationStep.create(
      order: template.steps.length,
      prompt: prompt,
      slotName: slotName,
      slotType: slotType,
      confirmationType: confirmationType,
    );

    final updatedSteps = [...template.steps, newStep];
    await updateTemplate(templateId: templateId, steps: updatedSteps);
  }

  // Update step
  Future<void> updateStep({
    required String templateId,
    required String stepId,
    String? prompt,
    String? slotName,
    bool clearSlotName = false,
    SlotType? slotType,
    ConfirmationType? confirmationType,
  }) async {
    final template = getTemplateById(templateId);
    if (template == null) return;

    final updatedSteps = template.steps.map((s) {
      if (s.id == stepId) {
        return s.copyWith(
          prompt: prompt,
          slotName: slotName,
          clearSlotName: clearSlotName,
          slotType: slotType,
          confirmationType: confirmationType,
        );
      }
      return s;
    }).toList();

    await updateTemplate(templateId: templateId, steps: updatedSteps);
  }

  // Delete step
  Future<void> deleteStep({
    required String templateId,
    required String stepId,
  }) async {
    final template = getTemplateById(templateId);
    if (template == null) return;

    final updatedSteps = template.steps
        .where((s) => s.id != stepId)
        .toList();

    // Reorder remaining steps
    for (var i = 0; i < updatedSteps.length; i++) {
      updatedSteps[i] = updatedSteps[i].copyWith(order: i);
    }

    await updateTemplate(templateId: templateId, steps: updatedSteps);
  }

  // Reorder steps
  Future<void> reorderSteps({
    required String templateId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final template = getTemplateById(templateId);
    if (template == null) return;

    final steps = List<ConversationStep>.from(template.steps);

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final step = steps.removeAt(oldIndex);
    steps.insert(newIndex, step);

    // Update order values
    for (var i = 0; i < steps.length; i++) {
      steps[i] = steps[i].copyWith(order: i);
    }

    await updateTemplate(templateId: templateId, steps: steps);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get available starter templates
  static List<StarterTemplate> get starterTemplates => [
    StarterTemplate(
      id: 'medical_intake',
      name: 'Medical Intake',
      description: 'Patient check-in for clinics and doctor offices',
      steps: [
        // Name - AI extracts and verifies spelling
        StarterStep(
          prompt: "Hi, I'll be helping you check in today. What is your full name?",
          slotName: 'patient_name',
          slotType: SlotType.name,
          confirmationType: ConfirmationType.explicitSpelling,
        ),
        // Phone - AI extracts digits, shown as a formatted number
        StarterStep(
          prompt: "What is a good phone number to reach you?",
          slotName: 'phone_number',
          slotType: SlotType.phone,
          confirmationType: ConfirmationType.explicit,
        ),
        // Reason - freeform with auto follow-up
        StarterStep(
          prompt: "What brings you in today?",
          slotName: 'reason_for_visit',
          slotType: SlotType.freeform,
          confirmationType: ConfirmationType.auto,
        ),
        // Duration - simple, quick echo
        StarterStep(
          prompt: "How long have you been experiencing this?",
          slotName: 'symptom_duration',
          slotType: SlotType.simple,
          confirmationType: ConfirmationType.implicit,
        ),
        // Pain level - simple, quick echo
        StarterStep(
          prompt: "On a scale of 1 to 10, how would you rate your discomfort?",
          slotName: 'pain_level',
          slotType: SlotType.simple,
          confirmationType: ConfirmationType.implicit,
        ),
        // Medications - freeform with auto follow-up
        StarterStep(
          prompt: "Are you currently taking any medications?",
          slotName: 'current_medications',
          slotType: SlotType.freeform,
          confirmationType: ConfirmationType.auto,
        ),
        // Allergies - freeform with auto follow-up
        StarterStep(
          prompt: "Do you have any allergies I should note?",
          slotName: 'allergies',
          slotType: SlotType.freeform,
          confirmationType: ConfirmationType.auto,
        ),
      ],
    ),
  ];

  /// Create a conversation from a starter template
  Future<ConversationTemplate> createFromStarterTemplate(String templateId) async {
    final starter = starterTemplates.firstWhere((t) => t.id == templateId);

    final template = ConversationTemplate.create(
      name: starter.name,
      description: starter.description,
    );

    // Add steps
    final steps = starter.steps.asMap().entries.map((entry) {
      return ConversationStep.create(
        order: entry.key,
        prompt: entry.value.prompt,
        slotName: entry.value.slotName,
        slotType: entry.value.slotType,
        confirmationType: entry.value.confirmationType,
      );
    }).toList();

    final templateWithSteps = template.copyWith(steps: steps);

    _templates.add(templateWithSteps);
    await _save();
    notifyListeners();

    return templateWithSteps;
  }
}

/// A starter template definition
class StarterTemplate {
  final String id;
  final String name;
  final String description;
  final List<StarterStep> steps;

  const StarterTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
  });
}

/// A step in a starter template
class StarterStep {
  final String prompt;
  final String? slotName;
  final SlotType slotType;
  final ConfirmationType confirmationType;

  const StarterStep({
    required this.prompt,
    this.slotName,
    this.slotType = SlotType.simple,
    this.confirmationType = ConfirmationType.auto,
  });
}
