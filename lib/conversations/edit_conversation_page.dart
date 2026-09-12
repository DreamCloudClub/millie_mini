import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class EditConversationPage extends StatefulWidget {
  final String? conversationId;
  final StarterTemplate? starterTemplate;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const EditConversationPage({
    super.key,
    this.conversationId,
    this.starterTemplate,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<EditConversationPage> createState() => _EditConversationPageState();
}

class _EditConversationPageState extends State<EditConversationPage> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _closingMessageController = TextEditingController();

  bool get isNewConversation => widget.conversationId == null && _template == null;
  bool get isFromTemplate => widget.starterTemplate != null && _template == null;
  ConversationTemplate? _template;
  List<ConversationStep>? _pendingSteps; // Steps from template before save

  // Get current steps from either saved template or pending
  List<ConversationStep> get _currentSteps => _template?.steps ?? _pendingSteps ?? [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversation();
    });
  }

  void _loadConversation() {
    if (widget.conversationId != null) {
      // Editing existing conversation
      final provider = context.read<ConversationTemplateProvider>();
      final template = provider.getTemplateById(widget.conversationId!);
      if (template != null) {
        setState(() {
          _template = template;
          _nameController.text = template.name;
          _descriptionController.text = template.description ?? '';
          _closingMessageController.text = template.closingMessage ?? '';
        });
      }
    } else if (widget.starterTemplate != null) {
      // Creating from a starter template - pre-fill but don't save yet
      final starter = widget.starterTemplate!;
      setState(() {
        _nameController.text = starter.name;
        _descriptionController.text = starter.description;
        _pendingSteps = starter.steps.asMap().entries.map((entry) {
          return ConversationStep.create(
            order: entry.key,
            prompt: entry.value.prompt,
            slotName: entry.value.slotName,
            slotType: entry.value.slotType,
            confirmationType: entry.value.confirmationType,
          );
        }).toList();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _closingMessageController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      return;
    }

    final provider = context.read<ConversationTemplateProvider>();

    if (_template == null) {
      // Creating new - either blank or from template
      final template = await provider.createTemplate(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        closingMessage: _closingMessageController.text.trim().isEmpty
            ? null
            : _closingMessageController.text.trim(),
      );

      // If we have pending steps from a template, add them
      if (_pendingSteps != null && _pendingSteps!.isNotEmpty) {
        await provider.updateTemplate(
          templateId: template.id,
          steps: _pendingSteps,
        );
      }

      // Activate the newly created conversation
      await provider.setActiveTemplate(template.id);

      setState(() {
        _template = provider.getTemplateById(template.id);
        _pendingSteps = null;
      });
    } else {
      // Updating existing
      await provider.updateTemplate(
        templateId: _template!.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        clearDescription: _descriptionController.text.trim().isEmpty,
        closingMessage: _closingMessageController.text.trim().isEmpty
            ? null
            : _closingMessageController.text.trim(),
        clearClosingMessage: _closingMessageController.text.trim().isEmpty,
      );
    }

    if (mounted) {
      widget.onSaved();
    }
  }

  Future<void> _handleDelete() async {
    if (isNewConversation || _template == null) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Conversation',
      message: 'This will permanently delete this conversation and all its steps.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed && mounted) {
      final provider = context.read<ConversationTemplateProvider>();
      await provider.deleteTemplate(widget.conversationId!);
      widget.onSaved();
    }
  }

  Future<void> _handleAddStep() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _StepEditorDialog(),
    );

    if (result != null && mounted) {
      final slotType = SlotType.values.firstWhere(
        (e) => e.name == result['slotType'],
        orElse: () => SlotType.simple,
      );
      final confirmationType = ConfirmationType.values.firstWhere(
        (e) => e.name == result['confirmationType'],
        orElse: () => ConfirmationType.auto,
      );

      final newStep = ConversationStep.create(
        order: _currentSteps.length,
        prompt: result['prompt']!,
        slotName: result['slotName']?.isEmpty == true ? null : result['slotName'],
        slotType: slotType,
        confirmationType: confirmationType,
      );

      if (_template != null) {
        final provider = context.read<ConversationTemplateProvider>();
        await provider.addStep(
          templateId: _template!.id,
          prompt: result['prompt']!,
          slotName: result['slotName']?.isEmpty == true ? null : result['slotName'],
          slotType: slotType,
          confirmationType: confirmationType,
        );
        _refreshTemplate();
      } else {
        // Working with pending steps
        setState(() {
          _pendingSteps = [...(_pendingSteps ?? []), newStep];
        });
      }
    }
  }

  Future<void> _handleEditStep(ConversationStep step) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _StepEditorDialog(
        initialPrompt: step.prompt,
        initialSlotName: step.slotName,
        initialSlotType: step.slotType,
        initialConfirmationType: step.confirmationType,
      ),
    );

    if (result != null && mounted) {
      final slotType = SlotType.values.firstWhere(
        (e) => e.name == result['slotType'],
        orElse: () => SlotType.simple,
      );
      final confirmationType = ConfirmationType.values.firstWhere(
        (e) => e.name == result['confirmationType'],
        orElse: () => ConfirmationType.auto,
      );

      if (_template != null) {
        final provider = context.read<ConversationTemplateProvider>();
        await provider.updateStep(
          templateId: _template!.id,
          stepId: step.id,
          prompt: result['prompt'],
          slotName: result['slotName'],
          clearSlotName: result['slotName']?.isEmpty == true,
          slotType: slotType,
          confirmationType: confirmationType,
        );
        _refreshTemplate();
      } else if (_pendingSteps != null) {
        setState(() {
          _pendingSteps = _pendingSteps!.map((s) {
            if (s.id == step.id) {
              return s.copyWith(
                prompt: result['prompt'],
                slotName: result['slotName'],
                clearSlotName: result['slotName']?.isEmpty == true,
                slotType: slotType,
                confirmationType: confirmationType,
              );
            }
            return s;
          }).toList();
        });
      }
    }
  }

  Future<void> _handleDeleteStep(ConversationStep step) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Step',
      message: 'Are you sure you want to delete this step?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed && mounted) {
      if (_template != null) {
        final provider = context.read<ConversationTemplateProvider>();
        await provider.deleteStep(
          templateId: _template!.id,
          stepId: step.id,
        );
        _refreshTemplate();
      } else if (_pendingSteps != null) {
        setState(() {
          _pendingSteps = _pendingSteps!.where((s) => s.id != step.id).toList();
          // Reorder
          for (var i = 0; i < _pendingSteps!.length; i++) {
            _pendingSteps![i] = _pendingSteps![i].copyWith(order: i);
          }
        });
      }
    }
  }

  void _refreshTemplate() {
    if (_template != null) {
      final provider = context.read<ConversationTemplateProvider>();
      setState(() {
        _template = provider.getTemplateById(_template!.id);
      });
    }
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (_template != null) {
      final provider = context.read<ConversationTemplateProvider>();
      provider.reorderSteps(
        templateId: _template!.id,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      _refreshTemplate();
    } else if (_pendingSteps != null) {
      setState(() {
        final steps = List<ConversationStep>.from(_pendingSteps!);

        if (newIndex > oldIndex) {
          newIndex -= 1;
        }

        final step = steps.removeAt(oldIndex);
        steps.insert(newIndex, step);

        // Update order values
        for (var i = 0; i < steps.length; i++) {
          steps[i] = steps[i].copyWith(order: i);
        }

        _pendingSteps = steps;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            isNewConversation ? 'Create Conversation' : 'Edit Conversation',
            style: AppTextStyles.heading2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name and Description
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Conversation Name',
                    hint: 'Enter a name for this conversation',
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Description (optional)', style: AppTextStyles.label),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Brief description of this conversation...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Steps Section
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Steps', style: AppTextStyles.heading3),
                      OutlinedButton.icon(
                        onPressed: _handleAddStep,
                        icon: const Icon(Icons.add, size: 18, color: AppColors.dreamCloudBlue),
                        label: const Text(
                          'Add Step',
                          style: TextStyle(
                            color: AppColors.dreamCloudBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dreamCloudBlue,
                          side: const BorderSide(
                            color: AppColors.dreamCloudBlue,
                            width: 1.5,
                          ),
                          backgroundColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_currentSteps.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Center(
                        child: Text(
                          'No steps yet. Add your first step!',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textLight,
                          ),
                        ),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _currentSteps.length,
                      onReorder: _handleReorder,
                      itemBuilder: (context, index) {
                        final step = _currentSteps[index];
                        return _StepCard(
                          key: ValueKey(step.id),
                          step: step,
                          index: index,
                          onEdit: () => _handleEditStep(step),
                          onDelete: () => _handleDeleteStep(step),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Closing Message Section
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
                border: Border.all(
                  color: AppColors.primaryOrange,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.celebration_outlined,
                        color: AppColors.primaryOrange,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Closing Message',
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.primaryOrange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Spoken and displayed after all steps are completed',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _closingMessageController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: ConversationTemplate.defaultClosingMessage,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Save Button
            AppButton(
              label: isNewConversation ? 'Create Conversation' : 'Save Changes',
              onPressed: _handleSave,
              isFullWidth: true,
              customColor: AppColors.dreamCloudBlue,
            ),

            // Delete Button
            if (!isNewConversation) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Delete Conversation',
                onPressed: _handleDelete,
                isFullWidth: true,
                customColor: AppColors.primaryOrange,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final ConversationStep step;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StepCard({
    super.key,
    required this.step,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  Color _slotTypeColor(SlotType type) {
    switch (type) {
      case SlotType.none:
        return AppColors.textLight;
      case SlotType.simple:
        return AppColors.success;
      case SlotType.name:
        return AppColors.dreamCloudBlue;
      case SlotType.datetime:
        return AppColors.primaryOrange;
      case SlotType.address:
        return Colors.teal;
      case SlotType.phone:
        return Colors.indigo;
      case SlotType.freeform:
        return Colors.purple;
    }
  }

  String _slotTypeShortLabel(SlotType type) {
    switch (type) {
      case SlotType.none:
        return 'none';
      case SlotType.simple:
        return 'simple';
      case SlotType.name:
        return 'name';
      case SlotType.datetime:
        return 'date/time';
      case SlotType.address:
        return 'address';
      case SlotType.phone:
        return 'phone';
      case SlotType.freeform:
        return 'freeform';
    }
  }

  String _confirmationShortLabel(ConfirmationType type) {
    switch (type) {
      case ConfirmationType.none:
        return 'no confirm';
      case ConfirmationType.implicit:
        return 'echo';
      case ConfirmationType.explicit:
        return 'confirm';
      case ConfirmationType.explicitSpelling:
        return 'spelling';
      case ConfirmationType.auto:
        return 'auto';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppBorderRadius.small),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Icon(
            Icons.drag_handle,
            color: AppColors.textLight,
          ),
          const SizedBox(width: AppSpacing.sm),
          // Step number
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.dreamCloudBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.prompt,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (step.capturesResponse) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.mic,
                        size: 14,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        step.slotName ?? 'response',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _slotTypeColor(step.slotType).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _slotTypeShortLabel(step.slotType),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: _slotTypeColor(step.slotType),
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.dreamCloudBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _confirmationShortLabel(step.confirmationType),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.dreamCloudBlue,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Actions
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                color: AppColors.dreamCloudBlue,
                onPressed: onEdit,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                color: AppColors.primaryOrange,
                onPressed: onDelete,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepEditorDialog extends StatefulWidget {
  final String? initialPrompt;
  final String? initialSlotName;
  final SlotType? initialSlotType;
  final ConfirmationType? initialConfirmationType;

  const _StepEditorDialog({
    this.initialPrompt,
    this.initialSlotName,
    this.initialSlotType,
    this.initialConfirmationType,
  });

  @override
  State<_StepEditorDialog> createState() => _StepEditorDialogState();
}

class _StepEditorDialogState extends State<_StepEditorDialog> {
  late final TextEditingController _promptController;
  late final TextEditingController _slotNameController;
  late SlotType _slotType;
  late ConfirmationType _confirmationType;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.initialPrompt ?? '');
    _slotNameController = TextEditingController(text: widget.initialSlotName ?? '');
    _slotType = widget.initialSlotType ?? SlotType.simple;
    _confirmationType = widget.initialConfirmationType ?? ConfirmationType.auto;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _slotNameController.dispose();
    super.dispose();
  }

  bool get _capturesResponse => _slotType != SlotType.none;

  String _slotTypeLabel(SlotType type) {
    switch (type) {
      case SlotType.none:
        return 'No response (statement only)';
      case SlotType.simple:
        return 'Simple (number, yes/no)';
      case SlotType.name:
        return 'Name (AI extracts & verifies)';
      case SlotType.datetime:
        return 'Date/Time (AI extracts & verifies)';
      case SlotType.address:
        return 'Address (AI extracts & verifies)';
      case SlotType.phone:
        return 'Phone number (shown as (555) 123-4567)';
      case SlotType.freeform:
        return 'Freeform (may need follow-up)';
    }
  }

  String _confirmationTypeLabel(ConfirmationType type) {
    switch (type) {
      case ConfirmationType.none:
        return 'None';
      case ConfirmationType.implicit:
        return 'Quick echo ("Got it, John.")';
      case ConfirmationType.explicit:
        return 'Ask to confirm ("Is that correct?")';
      case ConfirmationType.explicitSpelling:
        return 'Verify spelling ("Does that spelling look correct?")';
      case ConfirmationType.auto:
        return 'Auto (AI decides)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialPrompt == null ? 'Add Step' : 'Edit Step'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What should Millie ask?', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _promptController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter the question or statement...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Response Type', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<SlotType>(
                value: _slotType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                items: SlotType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(_slotTypeLabel(type), style: AppTextStyles.bodySmall),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _slotType = value ?? SlotType.simple;
                    // Set appropriate default confirmation based on slot type
                    switch (_slotType) {
                      case SlotType.none:
                        _slotNameController.clear();
                        _confirmationType = ConfirmationType.none;
                        break;
                      case SlotType.name:
                        _confirmationType = ConfirmationType.explicitSpelling;
                        break;
                      case SlotType.datetime:
                      case SlotType.address:
                      case SlotType.phone:
                        _confirmationType = ConfirmationType.explicit;
                        break;
                      case SlotType.simple:
                      case SlotType.freeform:
                        _confirmationType = ConfirmationType.auto;
                        break;
                    }
                  });
                },
              ),
              if (_capturesResponse) ...[
                const SizedBox(height: AppSpacing.md),
                const Text('Slot Name (field to save)', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _slotNameController,
                  decoration: InputDecoration(
                    hintText: 'e.g., patient_name, reason_for_visit',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text('Confirmation Style', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<ConfirmationType>(
                  value: _confirmationType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  items: ConfirmationType.values
                      .where((t) => t != ConfirmationType.none)
                      .map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_confirmationTypeLabel(type), style: AppTextStyles.bodySmall),
                  );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _confirmationType = value ?? ConfirmationType.auto;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_promptController.text.trim().isEmpty) return;
            Navigator.of(context).pop({
              'prompt': _promptController.text.trim(),
              'slotName': _capturesResponse ? _slotNameController.text.trim() : '',
              'slotType': _slotType.name,
              'confirmationType': _confirmationType.name,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.dreamCloudBlue,
          ),
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
