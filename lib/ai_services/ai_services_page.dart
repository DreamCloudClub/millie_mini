import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';

class AIServicesPage extends StatefulWidget {
  final VoidCallback onBack;

  const AIServicesPage({
    super.key,
    required this.onBack,
  });

  @override
  State<AIServicesPage> createState() => _AIServicesPageState();
}

class _AIServicesPageState extends State<AIServicesPage> {
  final _openaiKeyController = TextEditingController();
  bool _isTestingOpenAI = false;
  bool _openaiTestPassed = false;
  String? _openaiTestError;
  bool _obscureOpenAI = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final aiProvider = context.read<AIServiceProvider>();
    if (aiProvider.openaiApiKey != null) {
      _openaiKeyController.text = aiProvider.openaiApiKey!;
    }
  }

  @override
  void dispose() {
    _openaiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testOpenAIConnection() async {
    final key = _openaiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _openaiTestError = 'Please enter an API key first';
        _openaiTestPassed = false;
      });
      return;
    }

    setState(() {
      _isTestingOpenAI = true;
      _openaiTestError = null;
      _openaiTestPassed = false;
    });

    try {
      final testService = OpenAIService(StorageService());

      // Test by making a simple API call
      final isValid = await testService.testApiKey(key);

      setState(() {
        _isTestingOpenAI = false;
        if (isValid) {
          _openaiTestPassed = true;
          _openaiTestError = null;
        } else {
          _openaiTestPassed = false;
          _openaiTestError = 'Invalid API key or connection failed';
        }
      });
    } catch (e) {
      setState(() {
        _isTestingOpenAI = false;
        _openaiTestPassed = false;
        _openaiTestError = 'Connection test failed: ${e.toString()}';
      });
    }
  }

  Future<void> _saveKeys() async {
    final aiProvider = context.read<AIServiceProvider>();

    final openaiKey = _openaiKeyController.text.trim();

    bool saved = true;

    if (openaiKey.isNotEmpty) {
      saved = await aiProvider.saveOpenAIKey(openaiKey) && saved;
    }

    if (saved) {
      setState(() {
        _hasChanges = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API key saved'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'AI Service Settings',
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // OpenAI API Key Section
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.dreamCloudBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.smart_toy_outlined,
                          color: AppColors.dreamCloudBlue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OpenAI API Key',
                              style: AppTextStyles.heading3,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Required for chat, voice, and image generation',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _openaiKeyController,
                    obscureText: _obscureOpenAI,
                    onChanged: (_) => setState(() => _hasChanges = true),
                    decoration: InputDecoration(
                      hintText: 'sk-...',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.dreamCloudBlue,
                          width: 2,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureOpenAI
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.textLight,
                        ),
                        onPressed: () =>
                            setState(() => _obscureOpenAI = !_obscureOpenAI),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTestingOpenAI ? null : _testOpenAIConnection,
                          icon: _isTestingOpenAI
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.dreamCloudBlue,
                                  ),
                                )
                              : Icon(
                                  _openaiTestPassed
                                      ? Icons.check_circle
                                      : Icons.play_arrow,
                                  color: _openaiTestPassed
                                      ? AppColors.success
                                      : AppColors.dreamCloudBlue,
                                ),
                          label: Text(
                            _isTestingOpenAI
                                ? 'Testing...'
                                : _openaiTestPassed
                                    ? 'Connection OK'
                                    : 'Test Connection',
                            style: TextStyle(
                              color: _openaiTestPassed
                                  ? AppColors.success
                                  : AppColors.dreamCloudBlue,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.dreamCloudBlue,
                            side: BorderSide(
                              color: _openaiTestPassed
                                  ? AppColors.success
                                  : AppColors.dreamCloudBlue,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_openaiTestError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _openaiTestError!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Save Button
            AppButton(
              label: 'Save API Key',
              onPressed: _hasChanges ? _saveKeys : null,
              isFullWidth: true,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Help Text
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.dreamCloudBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.dreamCloudBlue.withValues(alpha: 0.2),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.dreamCloudBlue,
                        size: 20,
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Text(
                        'Getting an API Key',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.dreamCloudBlue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign up at platform.openai.com and create an API key in your account settings.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
