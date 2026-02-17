import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/openclaw_provider.dart';
import '../services/openclaw_service.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class OpenClawSettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const OpenClawSettingsPage({
    super.key,
    required this.onBack,
  });

  @override
  State<OpenClawSettingsPage> createState() => _OpenClawSettingsPageState();
}

class _OpenClawSettingsPageState extends State<OpenClawSettingsPage> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _enabled = false;
  bool _showToken = false;
  bool _isTesting = false;
  bool? _testResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  void _loadSettings() {
    final provider = context.read<OpenClawProvider>();
    setState(() {
      _enabled = provider.enabled;
      _urlController.text = provider.url;
      // Don't load token into text field for security
      // Show placeholder if token exists
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final provider = context.read<OpenClawProvider>();

    // Save URL
    if (_urlController.text.trim().isNotEmpty) {
      await provider.setUrl(_urlController.text.trim());
    }

    // Save token if changed
    if (_tokenController.text.isNotEmpty) {
      await provider.setToken(_tokenController.text.trim());
    }

    // Save enabled state
    await provider.setEnabled(_enabled);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onBack();
    }
  }

  Future<void> _handleTestConnection() async {
    final provider = context.read<OpenClawProvider>();

    // Apply current values temporarily for testing
    if (_urlController.text.trim().isNotEmpty) {
      await provider.setUrl(_urlController.text.trim());
    }
    if (_tokenController.text.isNotEmpty) {
      await provider.setToken(_tokenController.text.trim());
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final success = await provider.testConnection();

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = success;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Connection successful!'
              : 'Connection failed: ${provider.connectionError ?? "Unknown error"}'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Color _getStatusColor(OpenClawConnectionState state) {
    switch (state) {
      case OpenClawConnectionState.connected:
        return AppColors.success;
      case OpenClawConnectionState.connecting:
        return Colors.orange;
      case OpenClawConnectionState.error:
        return AppColors.error;
      case OpenClawConnectionState.disconnected:
        return AppColors.textLight;
    }
  }

  String _getStatusText(OpenClawConnectionState state) {
    switch (state) {
      case OpenClawConnectionState.connected:
        return 'Connected';
      case OpenClawConnectionState.connecting:
        return 'Connecting...';
      case OpenClawConnectionState.error:
        return 'Error';
      case OpenClawConnectionState.disconnected:
        return 'Disconnected';
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
            'OpenClaw Settings',
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
      body: Consumer<OpenClawProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.dreamCloudBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                    border: Border.all(
                      color: AppColors.dreamCloudBlue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.dreamCloudBlue,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'OpenClaw is used for conversations only. Games always use the standard AI service.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Settings card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Enable toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Enable OpenClaw',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Use OpenClaw for conversations',
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          ),
                          Switch(
                            value: _enabled,
                            onChanged: (value) {
                              setState(() {
                                _enabled = value;
                              });
                            },
                            activeColor: AppColors.dreamCloudBlue,
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.lg),

                      // Connection status
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getStatusColor(provider.connectionState),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Status: ${_getStatusText(provider.connectionState)}',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: _getStatusColor(provider.connectionState),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Connection URL
                      AppTextField(
                        label: 'Connection URL',
                        hint: OpenClawService.defaultUrl,
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                      ),

                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Default: ${OpenClawService.defaultUrl}',
                        style: AppTextStyles.bodySmall,
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Gateway Token
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gateway Token',
                            style: AppTextStyles.label,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          TextFormField(
                            controller: _tokenController,
                            obscureText: !_showToken,
                            style: AppTextStyles.bodyLarge,
                            decoration: InputDecoration(
                              hintText: provider.hasToken
                                  ? '••••••••••••••••'
                                  : 'Enter your gateway token',
                              hintStyle: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.textLight,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showToken
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: AppColors.textLight,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showToken = !_showToken;
                                  });
                                },
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.md,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppBorderRadius.small),
                                borderSide:
                                    const BorderSide(color: AppColors.divider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppBorderRadius.small),
                                borderSide:
                                    const BorderSide(color: AppColors.divider),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppBorderRadius.small),
                                borderSide: const BorderSide(
                                  color: AppColors.dreamCloudBlue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your token is stored securely on this device.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Test connection button
                OutlinedButton.icon(
                  onPressed: _isTesting || provider.isLoading
                      ? null
                      : _handleTestConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _testResult == true
                              ? Icons.check_circle
                              : _testResult == false
                                  ? Icons.error
                                  : Icons.wifi_find,
                          size: 20,
                        ),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _testResult == true
                        ? AppColors.success
                        : _testResult == false
                            ? AppColors.error
                            : AppColors.dreamCloudBlue,
                    side: BorderSide(
                      color: _testResult == true
                          ? AppColors.success
                          : _testResult == false
                              ? AppColors.error
                              : AppColors.dreamCloudBlue,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Save button
                AppButton(
                  label: 'Save Settings',
                  onPressed: provider.isLoading ? null : _handleSave,
                  isLoading: provider.isLoading,
                  isFullWidth: true,
                  customColor: AppColors.dreamCloudBlue,
                ),

                // Bottom safe area padding
                SizedBox(
                    height: MediaQuery.of(context).padding.bottom + AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }
}
