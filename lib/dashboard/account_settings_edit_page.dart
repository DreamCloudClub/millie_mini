import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class AccountSettingsEditPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const AccountSettingsEditPage({
    super.key,
    required this.onBack,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  State<AccountSettingsEditPage> createState() => _AccountSettingsEditPageState();
}

class _AccountSettingsEditPageState extends State<AccountSettingsEditPage> {
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  
  PermissionStatus _micPermission = PermissionStatus.denied;
  PermissionStatus _cameraPermission = PermissionStatus.denied;
  PermissionStatus _notificationPermission = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkPermissions();
  }

  void _loadData() {
    final user = context.read<AuthProvider>().userProfile;
    if (user != null) {
      _emailController.text = user.email;
    }
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
  void dispose() {
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdateEmail() async {
    if (_emailController.text.trim().isEmpty || 
        !_emailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.updateEmail(_emailController.text.trim());

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (authProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error!),
            backgroundColor: AppColors.error,
          ),
        );
        authProvider.clearError();
      }
    }
  }

  Future<void> _handleUpdatePassword() async {
    if (_currentPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current password is required'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 6 characters'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.updatePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
      confirmPassword: _confirmPasswordController.text,
    );

    if (mounted) {
      if (success) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (authProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error!),
            backgroundColor: AppColors.error,
          ),
        );
        authProvider.clearError();
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log Out',
      cancelLabel: 'Cancel',
    );

    if (confirmed && mounted) {
      await context.read<AuthProvider>().logout();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully'),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onLogout();
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Account',
      message: 'This will permanently delete your account and data. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange, // Changed from default error (red) to orange
    );

    if (confirmed && mounted) {
      final success = await context.read<AuthProvider>().deleteAccount();
      if (success && mounted) {
        widget.onDeleteAccount();
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
            'Account Settings',
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
            // Change Email Section
            _SectionCard(
              title: 'Change Email',
              child: Column(
                children: [
                  AppTextField(
                    label: 'New Email',
                    hint: 'Enter new email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) => AppButton(
                      label: 'Update Email',
                      onPressed: _handleUpdateEmail,
                      isLoading: auth.isLoading,
                      isFullWidth: true,
                      type: AppButtonType.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Change Password Section
            _SectionCard(
              title: 'Change Password',
              child: Column(
                children: [
                  AppTextField(
                    label: 'Current Password',
                    hint: 'Enter current password',
                    controller: _currentPasswordController,
                    obscureText: _obscureCurrent,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'New Password',
                    hint: 'Enter new password',
                    controller: _newPasswordController,
                    obscureText: _obscureNew,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Confirm New Password',
                    hint: 'Confirm new password',
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) => AppButton(
                      label: 'Update Password',
                      onPressed: _handleUpdatePassword,
                      isLoading: auth.isLoading,
                      isFullWidth: true,
                      type: AppButtonType.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

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
            const SizedBox(height: AppSpacing.md),

            // Logout Section
            _SectionCard(
              title: 'Logout',
              child: AppButton(
                label: 'Log Out',
                onPressed: _handleLogout,
                isFullWidth: true,
                type: AppButtonType.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Delete Account Section
            _SectionCard(
              title: 'Delete Account',
              child: AppButton(
                label: 'Delete Account',
                onPressed: _handleDeleteAccount,
                isFullWidth: true,
                customColor: AppColors.primaryOrange, // Changed from error (red) to orange
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
        return AppColors.dreamCloudBlue; // Changed from green to blue
      case PermissionStatus.denied:
      case PermissionStatus.permanentlyDenied:
        return AppColors.primaryOrange; // Changed from red to orange
      case PermissionStatus.restricted:
      case PermissionStatus.limited:
        return AppColors.primaryOrange; // Changed to orange for consistency
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    return SizedBox(
      width: 140, // Fixed width for all pills
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.25),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, // Minimal horizontal padding
            vertical: AppSpacing.sm, // Normal pill button vertical padding
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
