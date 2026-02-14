import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ai_service_provider.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class EditCustomServicePage extends StatefulWidget {
  final String? serviceId;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const EditCustomServicePage({
    super.key,
    this.serviceId,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<EditCustomServicePage> createState() => _EditCustomServicePageState();
}

class _EditCustomServicePageState extends State<EditCustomServicePage> {
  final _nameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  
  AIServiceType _serviceType = AIServiceType.openai;
  AIService? _existingService;
  
  bool get isNewService => widget.serviceId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadService();
    });
  }

  void _loadService() {
    if (!isNewService) {
      final service = context.read<AIServiceProvider>().getServiceById(widget.serviceId!);
      if (service != null) {
        _existingService = service;
        _nameController.text = service.displayName;
        setState(() {
          _serviceType = service.type;
        });
      }
    } else {
      _nameController.text = 'OpenAI - Home';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a display name'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (isNewService && _apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an API key'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final aiProvider = context.read<AIServiceProvider>();
    
    try {
      if (isNewService) {
        await aiProvider.addCustomService(
          type: _serviceType,
          displayName: _nameController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
        );
      } else {
        await aiProvider.updateService(
          serviceId: widget.serviceId!,
          displayName: _nameController.text.trim(),
          apiKey: _apiKeyController.text.trim().isEmpty 
              ? null 
              : _apiKeyController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNewService ? 'Service added' : 'Service updated'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(aiProvider.error ?? 'Failed to save service'),
            backgroundColor: AppColors.error,
          ),
        );
        aiProvider.clearError();
      }
    }
  }

  Future<void> _handleDelete() async {
    if (isNewService || _existingService == null) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Service',
      message: 'Delete this AI service? This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
    );

    if (confirmed && mounted) {
      final aiProvider = context.read<AIServiceProvider>();
      final success = await aiProvider.deleteService(widget.serviceId!);
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service deleted'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSaved();
      } else if (aiProvider.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(aiProvider.error!),
            backgroundColor: AppColors.error,
          ),
        );
        aiProvider.clearError();
      }
    }
  }

  void _updateDefaultName() {
    if (_nameController.text.isEmpty || 
        _nameController.text.startsWith('OpenAI') ||
        _nameController.text.startsWith('Gemini') ||
        _nameController.text.startsWith('Anthropic')) {
      _nameController.text = '${_serviceType.displayName} - Home';
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
            isNewService ? 'Add AI Service' : 'Edit AI Service',
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
      body: Consumer<AIServiceProvider>(
        builder: (context, aiProvider, _) {
          return SingleChildScrollView(
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
                      // Service Type
                      AppDropdown<AIServiceType>(
                        label: 'Service Type',
                        value: _serviceType,
                        items: [
                          AIServiceType.openai,
                          AIServiceType.gemini,
                          AIServiceType.anthropic,
                        ].map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.displayName),
                          );
                        }).toList(),
                        onChanged: isNewService ? (value) {
                          if (value != null) {
                            setState(() {
                              _serviceType = value;
                              _updateDefaultName();
                            });
                          }
                        } : null,
                        enabled: isNewService,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Display Name
                      AppTextField(
                        label: 'Display Name',
                        hint: 'e.g., OpenAI - Home',
                        controller: _nameController,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // API Key
                      AppTextField(
                        label: isNewService ? 'API Key' : 'API Key (leave blank to keep current)',
                        hint: 'Enter your API key',
                        controller: _apiKeyController,
                        obscureText: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your API key is stored securely and never shared.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                AppButton(
                  label: 'Save',
                  onPressed: _handleSave,
                  isLoading: aiProvider.isLoading,
                  isFullWidth: true,
                ),

                if (!isNewService) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Delete Service',
                    onPressed: _handleDelete,
                    isFullWidth: true,
                    customColor: AppColors.error,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }
}
