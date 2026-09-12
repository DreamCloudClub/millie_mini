import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import 'package:intl/intl.dart';

class ReportsPage extends StatelessWidget {
  final VoidCallback onBack;
  final void Function(String reportId) onViewReport;

  const ReportsPage({
    super.key,
    required this.onBack,
    required this.onViewReport,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Reports',
            style: AppTextStyles.heading2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: Consumer<ConversationReportProvider>(
        builder: (context, provider, _) {
          final reports = provider.completedReports;

          if (reports.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assessment_outlined,
                    size: 64,
                    color: AppColors.textLight,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No reports yet',
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Complete a conversation to see reports here',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];

              return _ReportCard(
                report: report,
                onView: () => onViewReport(report.id),
                onDelete: () async {
                  final confirmed = await ConfirmDialog.show(
                    context,
                    title: 'Delete Report',
                    message: 'Are you sure you want to delete this report?',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    isDangerous: true,
                    confirmColor: AppColors.primaryOrange,
                  );
                  if (confirmed) {
                    provider.deleteReport(report.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ConversationReport report;
  final VoidCallback onView;
  final VoidCallback onDelete;

  const _ReportCard({
    required this.report,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(AppBorderRadius.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.templateName,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${dateFormat.format(report.startedAt)} at ${timeFormat.format(report.startedAt)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${report.responses.length} response${report.responses.length == 1 ? '' : 's'} collected',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (report.duration != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Duration: ${_formatDuration(report.duration!)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Delete action only
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 22),
              color: AppColors.primaryOrange,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
  }
}
