import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/personality_provider.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

enum PersonalityBuilderMode { create, customize, edit }

class PersonalityBuilderPage extends StatefulWidget {
  final String? personalityId;
  final bool isCustomize;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const PersonalityBuilderPage({
    super.key,
    this.personalityId,
    this.isCustomize = false,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<PersonalityBuilderPage> createState() => _PersonalityBuilderPageState();
}

class _PersonalityBuilderPageState extends State<PersonalityBuilderPage> {
  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  
  Personality? _sourcePersonality;
  
  PersonalityBuilderMode get mode {
    if (widget.personalityId == null) return PersonalityBuilderMode.create;
    if (widget.isCustomize) return PersonalityBuilderMode.customize;
    return PersonalityBuilderMode.edit;
  }

  String get title {
    switch (mode) {
      case PersonalityBuilderMode.create:
        return 'Create Personality';
      case PersonalityBuilderMode.customize:
        return 'Customize Personality';
      case PersonalityBuilderMode.edit:
        return 'Edit Personality';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPersonality();
    });
  }

  void _loadPersonality() {
    if (widget.personalityId != null) {
      final personality = context.read<PersonalityProvider>()
          .getPersonalityById(widget.personalityId!);
      
      if (personality != null) {
        _sourcePersonality = personality;
        
        if (mode == PersonalityBuilderMode.customize) {
          _nameController.text = '${personality.name} (Custom)';
        } else {
          _nameController.text = personality.name;
        }
        _promptController.text = personality.behaviorPrompt;
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a personality name'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a behavior prompt'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final personalityProvider = context.read<PersonalityProvider>();
    
    switch (mode) {
      case PersonalityBuilderMode.create:
        await personalityProvider.createPersonality(
          name: _nameController.text.trim(),
          behaviorPrompt: _promptController.text.trim(),
        );
        break;
        
      case PersonalityBuilderMode.customize:
        await personalityProvider.customizePersonality(
          sourceId: widget.personalityId!,
          newName: _nameController.text.trim(),
          behaviorPrompt: _promptController.text.trim(),
        );
        break;
        
      case PersonalityBuilderMode.edit:
        await personalityProvider.updatePersonality(
          personalityId: widget.personalityId!,
          name: _nameController.text.trim(),
          behaviorPrompt: _promptController.text.trim(),
        );
        break;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Personality saved'),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onSaved();
    }
  }

  Future<void> _handleDelete() async {
    if (mode != PersonalityBuilderMode.edit || _sourcePersonality == null) return;
    
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Personality',
      message: 'Delete this personality? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
    );

    if (confirmed && mounted) {
      final personalityProvider = context.read<PersonalityProvider>();
      final success = await personalityProvider.deletePersonality(widget.personalityId!);
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Personality deleted'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSaved();
      } else if (personalityProvider.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(personalityProvider.error!),
            backgroundColor: AppColors.error,
          ),
        );
        personalityProvider.clearError();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = mode == PersonalityBuilderMode.edit && 
        _sourcePersonality != null && 
        !_sourcePersonality!.isDefault;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(title, style: AppTextStyles.heading2),
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    label: 'Personality Name',
                    hint: 'Enter a name for this personality',
                    controller: _nameController,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Behavior Prompt',
                    hint: 'Describe how this personality should behave...',
                    controller: _promptController,
                    maxLines: 8,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'This prompt describes the personality\'s behavior, tone, and style. '
                    'It will be used to guide how the AI responds. Use {agent_name} to refer to the agent by name.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            
            AppButton(
              label: 'Save Personality',
              onPressed: _handleSave,
              isFullWidth: true,
            ),
            
            if (canDelete) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Delete Personality',
                onPressed: _handleDelete,
                isFullWidth: true,
                customColor: AppColors.error,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
