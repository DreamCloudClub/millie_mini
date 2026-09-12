import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../models/custom_face.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/custom_face_service.dart';
import 'face_generator_page.dart';

/// Face type options
enum FaceType { robot, custom }

class EditAgentPage extends StatefulWidget {
  final String? agentId;
  final VoidCallback onBack;
  final VoidCallback onSaved;
  final void Function(String? personalityId, bool isCustomize) onEditPersonality;

  const EditAgentPage({
    super.key,
    this.agentId,
    required this.onBack,
    required this.onSaved,
    required this.onEditPersonality,
  });

  @override
  State<EditAgentPage> createState() => _EditAgentPageState();
}

class _EditAgentPageState extends State<EditAgentPage> {
  final _nameController = TextEditingController();
  final _introController = TextEditingController();

  FaceColor _faceColor = FaceColor.white;
  EyeShape _eyeShape = EyeShape.roundedSquares;
  String? _customFaceId;
  FaceType _faceType = FaceType.robot;
  bool _isEditingCustomFaces = false;
  List<CustomFace> _customFaces = [];
  String? _aiServiceId;
  String _voice = 'Alloy';
  String _voiceMode = 'turn_taking';
  String _personalityId = 'default_home';

  // Voice options based on mode
  static const List<String> turnTakingVoices = ['Alloy', 'Echo', 'Fable', 'Nova', 'Onyx', 'Shimmer'];
  static const List<String> realtimeVoices = ['alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse'];
  List<String> get voiceOptions => _voiceMode == 'realtime' ? realtimeVoices : turnTakingVoices;
  String _introMessage = 'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?';
  bool _showFaceGenerator = false;

  bool get isNewAgent => widget.agentId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAgent();
      _loadCustomFaces();
    });
  }

  Future<void> _loadCustomFaces() async {
    final faces = await CustomFaceService.loadAll();
    if (mounted) {
      setState(() {
        _customFaces = [...CustomFace.builtInFaces, ...faces];
      });
    }
  }

  void _loadAgent() {
    if (!isNewAgent) {
      final agent = context.read<AgentProvider>().getAgentById(widget.agentId!);
      if (agent != null) {
        _nameController.text = agent.name;
        _introController.text = agent.introMessage;
        setState(() {
          _faceColor = agent.faceColor;
          _eyeShape = agent.eyeShape;
          _customFaceId = agent.customFaceId;
          // Determine face type based on which ID is set
          if (agent.customFaceId != null) {
            _faceType = FaceType.custom;
          } else {
            _faceType = FaceType.robot;
          }
          _aiServiceId = 'openai_default'; // Always use OpenAI (migration from old services)
          _voiceMode = agent.voiceMode;
          // Ensure voice is valid for the mode
          final validVoices = _voiceMode == 'realtime' ? realtimeVoices : turnTakingVoices;
          _voice = validVoices.contains(agent.voice) ? agent.voice : validVoices.first;
          _personalityId = agent.personalityId;
          _introMessage = agent.introMessage;
        });
      }
    } else {
      _nameController.text = 'New Agent';
      _introController.text = _introMessage;
      _aiServiceId = 'openai_default';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _introController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      return;
    }

    final agentProvider = context.read<AgentProvider>();

    // Determine which face IDs to save based on face type
    String? faceImageId;
    String? customFaceId;
    bool clearFaceImageId = false;
    bool clearCustomFaceId = false;

    switch (_faceType) {
      case FaceType.robot:
        clearFaceImageId = true;
        clearCustomFaceId = true;
        break;
      case FaceType.custom:
        customFaceId = _customFaceId;
        clearFaceImageId = true;
        break;
    }

    if (isNewAgent) {
      await agentProvider.createAgent(
        name: _nameController.text.trim(),
        faceColor: _faceColor,
        eyeShape: _eyeShape,
        faceImageId: faceImageId,
        customFaceId: customFaceId,
        aiServiceId: _aiServiceId ?? 'openai_default',
        voice: _voice,
        voiceMode: _voiceMode,
        personalityId: _personalityId,
        introMessage: _introController.text.trim(),
      );
    } else {
      await agentProvider.updateAgent(
        agentId: widget.agentId!,
        name: _nameController.text.trim(),
        faceColor: _faceColor,
        eyeShape: _eyeShape,
        faceImageId: faceImageId,
        clearFaceImageId: clearFaceImageId,
        customFaceId: customFaceId,
        clearCustomFaceId: clearCustomFaceId,
        aiServiceId: _aiServiceId,
        voice: _voice,
        voiceMode: _voiceMode,
        personalityId: _personalityId,
        introMessage: _introController.text.trim(),
      );
    }

    if (mounted) {
      widget.onSaved();
    }
  }

  Future<void> _handleDeleteCustomFace(String id) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Custom Face',
      message: 'This will permanently delete this custom face. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed == true) {
      final success = await CustomFaceService.deleteFace(id);
      if (success && mounted) {
        // Refresh the provider cache
        context.read<CustomFaceProvider>().refresh();
        setState(() {
          _customFaces.removeWhere((f) => f.id == id);
          if (_customFaceId == id) {
            _customFaceId = null;
          }
        });
      }
    }
  }

  Future<void> _handleDelete() async {
    if (isNewAgent) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Agent',
      message: 'This will permanently delete this agent. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed && mounted) {
      final agentProvider = context.read<AgentProvider>();
      await agentProvider.deleteAgent(widget.agentId!);

      if (mounted && agentProvider.error == null) {
        widget.onSaved();
      } else {
        agentProvider.clearError();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show face generator page if active
    if (_showFaceGenerator) {
      return FaceGeneratorPage(
        onBack: () {
          setState(() {
            _showFaceGenerator = false;
          });
        },
        onFaceSaved: (face) {
          // Refresh the provider cache so FacePageContent can find it
          context.read<CustomFaceProvider>().refresh();
          setState(() {
            _showFaceGenerator = false;
            _customFaces.add(face);
            _customFaceId = face.id;
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            isNewAgent ? 'Create Agent' : 'Edit Agent',
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Face Preview
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Center(
                child: FacePreview(
                  faceColor: _faceColor,
                  eyeShape: _eyeShape,
                  faceImageId: null,
                  customFaceId: _faceType == FaceType.custom ? _customFaceId : null,
                  size: 160,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Face Type Selector
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Face Type', style: AppTextStyles.label),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _FaceTypeButton(
                          label: 'Robot',
                          isSelected: _faceType == FaceType.robot,
                          onTap: () {
                            setState(() {
                              _faceType = FaceType.robot;
                              _isEditingCustomFaces = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _FaceTypeButton(
                          label: 'Custom',
                          isSelected: _faceType == FaceType.custom,
                          onTap: () {
                            setState(() {
                              _faceType = FaceType.custom;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  // Custom faces grid
                  if (_faceType == FaceType.custom) ...[
                    const SizedBox(height: AppSpacing.md),
                    _CustomFaceGrid(
                      customFaces: _customFaces,
                      selectedId: _customFaceId,
                      isEditing: _isEditingCustomFaces,
                      onSelect: (id) {
                        setState(() {
                          _customFaceId = id;
                        });
                      },
                      onAdd: () {
                        setState(() {
                          _showFaceGenerator = true;
                        });
                      },
                      onDelete: (id) => _handleDeleteCustomFace(id),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Edit button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isEditingCustomFaces = !_isEditingCustomFaces;
                          });
                        },
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
                        child: Text(
                          _isEditingCustomFaces ? 'Done' : 'Edit Faces',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Agent Settings
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final agentProvider = context.read<AgentProvider>();
                      final isDefaultMillie = !isNewAgent && 
                          agentProvider.isDefaultMillieAgent(widget.agentId!);
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppTextField(
                            label: 'Agent Name',
                            hint: 'Enter agent name',
                            controller: _nameController,
                            enabled: !isDefaultMillie,
                            textCapitalization: TextCapitalization.words,
                          ),
                          if (isDefaultMillie) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'The default agent name cannot be changed',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Face Color (only show for robot face)
                  if (_faceType == FaceType.robot) ...[
                    AppDropdown<FaceColor>(
                      label: 'Face Color',
                      value: _faceColor,
                      items: FaceColor.values.map((color) {
                        return DropdownMenuItem(
                          value: color,
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: color.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.divider),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(color.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _faceColor = value);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Eye Shape
                    AppDropdown<EyeShape>(
                      label: 'Eye Shape',
                      value: _eyeShape,
                      items: EyeShape.values.map((shape) {
                        return DropdownMenuItem(
                          value: shape,
                          child: Text(shape.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _eyeShape = value);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],


                  // Voice Mode Dropdown (before Voice so voice list updates first)
                  AppDropdown<String>(
                    label: 'Voice Mode',
                    value: _voiceMode,
                    items: const [
                      DropdownMenuItem(
                        value: 'turn_taking',
                        child: Text('Turn-taking'),
                      ),
                      DropdownMenuItem(
                        value: 'realtime',
                        child: Text('Realtime'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _voiceMode = value;
                          // Always reset to first voice in new mode to avoid case mismatch
                          _voice = value == 'realtime' ? realtimeVoices.first : turnTakingVoices.first;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Voice
                  AppDropdown<String>(
                    label: 'Voice',
                    value: _voice,
                    items: voiceOptions.map((voice) {
                      return DropdownMenuItem(
                        value: voice,
                        child: Text(voice),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _voice = value);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Intro Message
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Intro Message',
                        style: AppTextStyles.label,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _introController,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: 'Hello {username}, it\'s me {agent_name}...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppBorderRadius.small),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (value) {
                          setState(() => _introMessage = value);
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Use {username} and {agent_name} to personalize the greeting. Example: "Hello {username}, it\'s me {agent_name}, how can I help?"',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Personalities Section
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
                      const Text('Personalities', style: AppTextStyles.heading3),
                      OutlinedButton.icon(
                        onPressed: () => widget.onEditPersonality(null, false),
                        icon: const Icon(Icons.add, size: 18, color: AppColors.dreamCloudBlue),
                        label: const Text(
                          'Create New',
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
                  Consumer<PersonalityProvider>(
                    builder: (context, personalityProvider, _) {
                      return Column(
                        children: personalityProvider.personalities.map((p) {
                          return _PersonalityRow(
                            personality: p,
                            isActive: _personalityId == p.id,
                            onActivate: () {
                              setState(() => _personalityId = p.id);
                            },
                            onEdit: () {
                              if (p.isDefault) {
                                widget.onEditPersonality(p.id, true);
                              } else {
                                widget.onEditPersonality(p.id, false);
                              }
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Save Button
            AppButton(
              label: 'Save Agent',
              onPressed: _handleSave,
              isFullWidth: true,
              customColor: AppColors.dreamCloudBlue,
            ),
            
            // Delete Agent button (only show when editing, and not for default Millie)
            if (!isNewAgent) ...[
              Builder(
                builder: (context) {
                  final agentProvider = context.read<AgentProvider>();
                  final isDefaultMillie = agentProvider.isDefaultMillieAgent(widget.agentId!);
                  
                  if (isDefaultMillie) {
                    // Don't show delete button for default Millie
                    return const SizedBox.shrink();
                  }
                  
                  return Column(
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Delete Agent',
                        onPressed: _handleDelete,
                        isFullWidth: true,
                        customColor: AppColors.primaryOrange,
                      ),
                    ],
                  );
                },
              ),
            ],
            
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _FaceTypeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FaceTypeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.dreamCloudBlue.withOpacity(0.15)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(AppBorderRadius.small),
          border: Border.all(
            color: isSelected ? AppColors.dreamCloudBlue : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isSelected ? AppColors.dreamCloudBlue : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _CustomFaceGrid extends StatelessWidget {
  final List<CustomFace> customFaces;
  final String? selectedId;
  final bool isEditing;
  final void Function(String) onSelect;
  final VoidCallback onAdd;
  final void Function(String) onDelete;

  const _CustomFaceGrid({
    required this.customFaces,
    required this.selectedId,
    required this.isEditing,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Include add card as first item
    final itemCount = customFaces.length + 1;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // First item is the "Add" card
        if (index == 0) {
          return GestureDetector(
            onTap: onAdd,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(AppBorderRadius.small),
                border: Border.all(
                  color: AppColors.divider,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add,
                    size: 28,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Custom face items
        final face = customFaces[index - 1];
        final isSelected = face.id == selectedId;

        return GestureDetector(
          onTap: isEditing ? null : () => onSelect(face.id),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.faceBackground,
                  borderRadius: BorderRadius.circular(AppBorderRadius.small),
                  border: Border.all(
                    color: isSelected ? AppColors.dreamCloudBlue : AppColors.divider,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppBorderRadius.small - 2),
                  child: face.isBuiltIn
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Image.asset(face.localPath, fit: BoxFit.contain),
                        )
                      : Image.file(
                          File(face.localPath),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade300,
                            child: const Center(
                              child: Icon(Icons.face, color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                ),
              ),
              // Delete button (only in edit mode; built-ins can't be deleted)
              if (isEditing && !face.isBuiltIn)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => onDelete(face.id),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrange,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonalityRow extends StatelessWidget {
  final Personality personality;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEdit;

  const _PersonalityRow({
    required this.personality,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  personality.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (personality.isDefault)
                  Text(
                    'Default',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: isActive
                ? ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success.withOpacity(0.25),
                      foregroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      disabledBackgroundColor: AppColors.success.withOpacity(0.25),
                      disabledForegroundColor: AppColors.success,
                      elevation: 0,
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  )
                : ElevatedButton(
                    onPressed: onActivate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange.withOpacity(0.25),
                      foregroundColor: AppColors.primaryOrange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Activate',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 100,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.dreamCloudBlue,
                side: const BorderSide(
                  color: AppColors.dreamCloudBlue,
                  width: 1.5,
                ),
                backgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                personality.isDefault ? 'Customize' : 'Edit',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
