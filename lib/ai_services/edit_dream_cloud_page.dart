import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class EditDreamCloudPage extends StatefulWidget {
  final VoidCallback onBack;
  
  const EditDreamCloudPage({
    super.key,
    required this.onBack,
  });

  @override
  State<EditDreamCloudPage> createState() => _EditDreamCloudPageState();
}

class _EditDreamCloudPageState extends State<EditDreamCloudPage> {
  final _emailController = TextEditingController();
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final aiProvider = context.read<AIServiceProvider>();
    final dreamCloud = aiProvider.dreamCloudService;
    
    if (dreamCloud?.subscriptionEmail != null) {
      _emailController.text = dreamCloud!.subscriptionEmail!;
    } else {
      // Default to login email
      final authProvider = context.read<AuthProvider>();
      _emailController.text = authProvider.userProfile?.email ?? '';
    }
    
    _updateStatusMessage(dreamCloud?.status);
  }

  void _updateStatusMessage(AIServiceStatus? status) {
    switch (status) {
      case AIServiceStatus.holder:
        _statusMessage = 'Crypto Holder access active. Thank you for holding!';
        break;
      case AIServiceStatus.basic:
        _statusMessage = 'Basic subscription active';
        break;
      case AIServiceStatus.pro:
        _statusMessage = 'Pro subscription active';
        break;
      case AIServiceStatus.active:
        _statusMessage = 'Subscription active';
        break;
      case AIServiceStatus.trial:
        _statusMessage = 'Trial subscription active';
        break;
      case AIServiceStatus.pending:
        _statusMessage = 'Subscription pending payment. Please complete payment at dreamcloudclub.org';
        break;
      case AIServiceStatus.expired:
        _statusMessage = 'Subscription expired. Please renew at dreamcloudclub.org';
        break;
      case AIServiceStatus.inactive:
        _statusMessage = 'No active subscription. Subscribe at dreamcloudclub.org';
        break;
      case AIServiceStatus.notFound:
        _statusMessage = 'Email not found. Please sign up at dreamcloudclub.org';
        break;
      default:
        _statusMessage = 'Not configured';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final aiProvider = context.read<AIServiceProvider>();
    await aiProvider.updateDreamCloudSubscription(_emailController.text.trim());

    if (mounted) {
      final dreamCloud = aiProvider.dreamCloudService;
      setState(() {
        _updateStatusMessage(dreamCloud?.status);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aiProvider.error ?? 'Settings saved'),
          backgroundColor: dreamCloud?.status == AIServiceStatus.active
              ? AppColors.success
              : AppColors.primaryOrange,
        ),
      );
      aiProvider.clearError();
    }
  }

  String _statusText(AIServiceStatus? status) {
    return status?.displayName ?? 'Unknown';
  }

  Color _statusColor(AIServiceStatus? status) {
    switch (status) {
      case AIServiceStatus.holder:
        return Colors.amber;  // Gold for crypto holders 🏆
      case AIServiceStatus.basic:
        return AppColors.success;
      case AIServiceStatus.pro:
        return Colors.blue;  // Blue for pro tier
      case AIServiceStatus.active:
        return AppColors.success;
      case AIServiceStatus.trial:
        return Colors.blue;
      case AIServiceStatus.pending:
        return Colors.orange;
      case AIServiceStatus.expired:
      case AIServiceStatus.inactive:
      case AIServiceStatus.notFound:
        return AppColors.error;
      default:
        return AppColors.textLight;
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
            'Dream Cloud AI Account',
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
          final dreamCloud = aiProvider.dreamCloudService;

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
                      // Status
                      Row(
                        children: [
                          Text(
                            'Status',
                            style: AppTextStyles.label.copyWith(fontSize: 18),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _statusColor(dreamCloud?.status).withOpacity(0.25),
                              foregroundColor: _statusColor(dreamCloud?.status),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              disabledBackgroundColor: _statusColor(dreamCloud?.status).withOpacity(0.25),
                              disabledForegroundColor: _statusColor(dreamCloud?.status),
                              elevation: 0,
                            ),
                            child: Text(
                              _statusText(dreamCloud?.status),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _statusMessage,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: dreamCloud?.status == AIServiceStatus.active
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.md),

                      // Email
                      AppTextField(
                        label: 'Subscription Email',
                        hint: 'Enter your subscription email',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Enter the email associated with your Dream Cloud AI subscription.',
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
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }
}
