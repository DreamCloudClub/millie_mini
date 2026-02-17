import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/image_cache_service.dart';

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
  String? _faceImageId;
  bool _useAnimalFace = false;
  String? _aiServiceId;
  String _voice = 'Alloy';
  String _personalityId = 'default_home';
  String _introMessage = 'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?';

  bool get isNewAgent => widget.agentId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAgent();
    });
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
          _faceImageId = agent.faceImageId;
          _useAnimalFace = agent.faceImageId != null;
          _aiServiceId = agent.aiServiceId;
          _voice = agent.voice;
          _personalityId = agent.personalityId;
          _introMessage = agent.introMessage;
        });
      }
    } else {
      _nameController.text = 'New Agent';
      _introController.text = _introMessage;
      _aiServiceId = context.read<AIServiceProvider>().dreamCloudService?.id;
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

    if (isNewAgent) {
      await agentProvider.createAgent(
        name: _nameController.text.trim(),
        faceColor: _faceColor,
        eyeShape: _eyeShape,
        faceImageId: _useAnimalFace ? _faceImageId : null,
        aiServiceId: _aiServiceId ?? 'dream_cloud_default',
        voice: _voice,
        personalityId: _personalityId,
        introMessage: _introController.text.trim(),
      );
    } else {
      await agentProvider.updateAgent(
        agentId: widget.agentId!,
        name: _nameController.text.trim(),
        faceColor: _faceColor,
        eyeShape: _eyeShape,
        faceImageId: _useAnimalFace ? _faceImageId : null,
        clearFaceImageId: !_useAnimalFace,
        aiServiceId: _aiServiceId,
        voice: _voice,
        personalityId: _personalityId,
        introMessage: _introController.text.trim(),
      );
    }

    if (mounted) {
      widget.onSaved();
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
                  faceImageId: _useAnimalFace ? _faceImageId : null,
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
                          label: 'Robot Face',
                          isSelected: !_useAnimalFace,
                          onTap: () {
                            setState(() {
                              _useAnimalFace = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _FaceTypeButton(
                          label: 'Animal Face',
                          isSelected: _useAnimalFace,
                          onTap: () {
                            setState(() {
                              _useAnimalFace = true;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_useAnimalFace) ...[
                    const SizedBox(height: AppSpacing.md),
                    Consumer<FaceImageProvider>(
                      builder: (context, faceImageProvider, _) {
                        final faceImages = faceImageProvider.faceImages;
                        if (faceImages.isEmpty) {
                          return const Center(
                            child: Text(
                              'No animal faces available',
                              style: AppTextStyles.bodySmall,
                            ),
                          );
                        }
                        return _FaceImageGrid(
                          faceImages: faceImages,
                          selectedId: _faceImageId,
                          onSelect: (id) {
                            setState(() {
                              _faceImageId = id;
                            });
                          },
                        );
                      },
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
                  if (!_useAnimalFace) ...[
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

                  // AI Service
                  Consumer<AIServiceProvider>(
                    builder: (context, aiProvider, _) {
                      return AppDropdown<String>(
                        label: 'AI Service',
                        value: _aiServiceId,
                        items: aiProvider.services.map((service) {
                          return DropdownMenuItem(
                            value: service.id,
                            child: Text(service.displayName),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _aiServiceId = value;
                              // Update voice to first available for new service
                              final voices = aiProvider.getVoicesForService(value);
                              if (voices.isNotEmpty && !voices.contains(_voice)) {
                                _voice = voices.first;
                              }
                            });
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Voice
                  Consumer<AIServiceProvider>(
                    builder: (context, aiProvider, _) {
                      final voices = _aiServiceId != null 
                          ? aiProvider.getVoicesForService(_aiServiceId!)
                          : <String>[];
                      return AppDropdown<String>(
                        label: 'Voice',
                        value: voices.contains(_voice) ? _voice : voices.firstOrNull,
                        items: voices.map((voice) {
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
                      );
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

class _FaceImageGrid extends StatelessWidget {
  final List<FaceImage> faceImages;
  final String? selectedId;
  final void Function(String) onSelect;

  const _FaceImageGrid({
    required this.faceImages,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1,
      ),
      itemCount: faceImages.length,
      itemBuilder: (context, index) {
        final face = faceImages[index];
        final isSelected = face.id == selectedId;
        final localPath = ImageCacheService.getFaceLocalPath(face.imageUrl);

        return GestureDetector(
          onTap: () => onSelect(face.id),
          child: Container(
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
              child: localPath != null
                  ? Image.file(
                      File(localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(face.name),
                    )
                  : face.imageUrl.isNotEmpty
                      ? Image.network(
                          face.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(face.name),
                        )
                      : _buildPlaceholder(face.name),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(String name) {
    return Container(
      color: Colors.grey.shade300,
      child: Center(
        child: Text(
          name[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
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
