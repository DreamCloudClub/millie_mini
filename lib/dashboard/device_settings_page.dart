import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class DeviceSettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const DeviceSettingsPage({
    super.key,
    required this.onBack,
  });

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  PermissionStatus _micPermission = PermissionStatus.denied;
  PermissionStatus _cameraPermission = PermissionStatus.denied;
  PermissionStatus _notificationPermission = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final mic = await Permission.microphone.status;
    final camera = await Permission.camera.status;
    final notification = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _micPermission = mic;
        _cameraPermission = camera;
        _notificationPermission = notification;
      });
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
            'Device Settings',
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
          children: [
            // Device Permissions Section
            _SectionCard(
              title: 'Device Permissions',
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Microphone', style: AppTextStyles.bodyMedium),
                      _PermissionStatusButton(status: _micPermission),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Camera', style: AppTextStyles.bodyMedium),
                      _PermissionStatusButton(status: _cameraPermission),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Notifications', style: AppTextStyles.bodyMedium),
                      _PermissionStatusButton(status: _notificationPermission),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Open App Settings',
                    onPressed: () => openAppSettings(),
                    isFullWidth: true,
                    type: AppButtonType.outline,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _PermissionStatusButton extends StatelessWidget {
  final PermissionStatus status;

  const _PermissionStatusButton({
    required this.status,
  });

  String _getStatusText() {
    switch (status) {
      case PermissionStatus.granted:
        return 'Granted';
      case PermissionStatus.denied:
        return 'Denied';
      case PermissionStatus.restricted:
        return 'Restricted';
      case PermissionStatus.limited:
        return 'Limited';
      case PermissionStatus.permanentlyDenied:
        return 'Permanently Denied';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor() {
    switch (status) {
      case PermissionStatus.granted:
        return AppColors.dreamCloudBlue;
      case PermissionStatus.denied:
      case PermissionStatus.permanentlyDenied:
        return AppColors.primaryOrange;
      case PermissionStatus.restricted:
      case PermissionStatus.limited:
        return AppColors.primaryOrange;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    return SizedBox(
      width: 140,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.25),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          disabledBackgroundColor: color.withValues(alpha: 0.25),
          disabledForegroundColor: color,
          elevation: 0,
        ),
        child: Text(
          _getStatusText(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
