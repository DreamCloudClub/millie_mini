import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/openclaw_provider.dart';
import '../services/openclaw_service.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class BrainSettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const BrainSettingsPage({
    super.key,
    required this.onBack,
  });

  @override
  State<BrainSettingsPage> createState() => _BrainSettingsPageState();
}

class _BrainSettingsPageState extends State<BrainSettingsPage> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _enabled = false;
  bool _showToken = false;
  bool _isTesting = false;
  bool? _testResult;

  // Brain status
  bool _isLoadingStatus = false;
  bool _isOnline = false;
  String? _temperature;
  String? _uptime;
  String? _memory;
  String? _ipAddress;

  // Power actions
  bool _isShuttingDown = false;
  bool _isRebooting = false;

  String get _brainApiUrl {
    // Derive API URL from OpenClaw URL (same host, port 8080)
    final openclawUrl = _urlController.text.trim();
    if (openclawUrl.isEmpty) return 'http://brain.local:8080';

    try {
      final uri = Uri.parse(openclawUrl);
      return 'http://${uri.host}:8080';
    } catch (_) {
      return 'http://brain.local:8080';
    }
  }

  String get _token {
    final provider = context.read<OpenClawProvider>();
    return _tokenController.text.isNotEmpty
        ? _tokenController.text
        : (provider.hasToken ? 'brain' : '');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
      _fetchStatus();
    });
  }

  void _loadSettings() {
    final provider = context.read<OpenClawProvider>();
    setState(() {
      _enabled = provider.enabled;
      _urlController.text = provider.url.isNotEmpty
          ? provider.url
          : 'ws://brain.local:18789';
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    setState(() => _isLoadingStatus = true);

    try {
      final response = await http.get(
        Uri.parse('$_brainApiUrl/status'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isOnline = data['online'] ?? false;
          _temperature = data['temperature']?.toString();
          _uptime = data['uptime'];
          _memory = data['memory'];
          _ipAddress = data['ip'];
        });
      } else {
        setState(() => _isOnline = false);
      }
    } catch (e) {
      setState(() => _isOnline = false);
    } finally {
      setState(() => _isLoadingStatus = false);
    }
  }

  Future<void> _handleShutdown() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shutdown Brain?'),
        content: const Text('This will turn off the Pi. You\'ll need physical access to turn it back on.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Shutdown'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isShuttingDown = true);

    try {
      await http.post(
        Uri.parse('$_brainApiUrl/shutdown'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brain is shutting down...'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to shutdown: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isShuttingDown = false);
    }
  }

  Future<void> _handleReboot() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reboot Brain?'),
        content: const Text('This will restart the Pi. It may take a minute to come back online.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Reboot'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRebooting = true);

    try {
      await http.post(
        Uri.parse('$_brainApiUrl/reboot'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brain is rebooting...'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reboot: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isRebooting = false);
    }
  }

  Future<void> _handleSave() async {
    final provider = context.read<OpenClawProvider>();

    if (_urlController.text.trim().isNotEmpty) {
      await provider.setUrl(_urlController.text.trim());
    }

    if (_tokenController.text.isNotEmpty) {
      await provider.setToken(_tokenController.text.trim());
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Brain Settings',
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
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Card
                _buildStatusCard(),

                const SizedBox(height: AppSpacing.md),

                // Power Controls Card
                _buildPowerCard(),

                const SizedBox(height: AppSpacing.md),

                // OpenClaw Config Card
                _buildOpenClawCard(provider),

                const SizedBox(height: AppSpacing.xl),

                // Save button
                AppButton(
                  label: 'Save Settings',
                  onPressed: provider.isLoading ? null : _handleSave,
                  isLoading: provider.isLoading,
                  isFullWidth: true,
                  customColor: AppColors.dreamCloudBlue,
                ),

                SizedBox(
                    height: MediaQuery.of(context).padding.bottom + AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isOnline ? AppColors.success : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _isOnline ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _isLoadingStatus ? null : _fetchStatus,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isLoadingStatus
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 20, color: Colors.white),
                ),
              ),
            ],
          ),
          if (_isOnline) ...[
            const Divider(),
            const SizedBox(height: AppSpacing.xs),
            if (_ipAddress != null)
              _buildStatusRow('IP Address', _ipAddress!),
            if (_temperature != null)
              _buildStatusRow('Temperature', '$_temperature°C'),
            if (_uptime != null)
              _buildStatusRow('Uptime', _uptime!.replaceFirst('up ', '')),
            if (_memory != null)
              _buildStatusRow('Memory', _memory!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Text(value, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildPowerCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Power',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isRebooting || !_isOnline ? null : _handleReboot,
                  icon: _isRebooting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restart_alt, size: 20),
                  label: const Text('Reboot'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isShuttingDown || !_isOnline ? null : _handleShutdown,
                  icon: _isShuttingDown
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new, size: 20),
                  label: const Text('Shutdown'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpenClawCard(OpenClawProvider provider) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'OpenClaw',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
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

          Text(
            'Use OpenClaw for conversations',
            style: AppTextStyles.bodySmall,
          ),

          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),

          // Connection status
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: provider.connectionState == OpenClawConnectionState.connected
                      ? AppColors.success
                      : provider.connectionState == OpenClawConnectionState.connecting
                          ? Colors.orange
                          : AppColors.textLight,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                provider.connectionState == OpenClawConnectionState.connected
                    ? 'Connected'
                    : provider.connectionState == OpenClawConnectionState.connecting
                        ? 'Connecting...'
                        : 'Disconnected',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Connection URL
          AppTextField(
            label: 'Connection URL',
            hint: 'ws://brain.local:18789',
            controller: _urlController,
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: AppSpacing.md),

          // Gateway Token
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gateway Token', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _tokenController,
                obscureText: !_showToken,
                style: AppTextStyles.bodyLarge,
                decoration: InputDecoration(
                  hintText: provider.hasToken ? '••••••••' : 'Enter token',
                  hintStyle: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textLight,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textLight,
                    ),
                    onPressed: () {
                      setState(() => _showToken = !_showToken);
                    },
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    borderSide: const BorderSide(
                      color: AppColors.dreamCloudBlue,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Test connection button
          OutlinedButton.icon(
            onPressed: _isTesting || provider.isLoading ? null : _handleTestConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
            ),
          ),
        ],
      ),
    );
  }
}
