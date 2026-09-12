import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import 'package:intl/intl.dart';

class ViewReportPage extends StatelessWidget {
  final String reportId;
  final VoidCallback onBack;

  const ViewReportPage({
    super.key,
    required this.reportId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationReportProvider>(
      builder: (context, provider, _) {
        final report = provider.getReportById(reportId);

        if (report == null) {
          return Scaffold(
            backgroundColor: Colors.grey.shade100,
            appBar: AppBar(
              title: const Text('Report'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
            ),
            body: const Center(
              child: Text('Report not found'),
            ),
          );
        }

        final dateFormat = DateFormat('MMMM d, yyyy');
        final timeFormat = DateFormat('h:mm a');

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            title: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                report.templateName,
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Summary', style: AppTextStyles.heading3),
                      const SizedBox(height: AppSpacing.md),
                      _SummaryRow(
                        label: 'Completed',
                        value: '${dateFormat.format(report.startedAt)} at ${timeFormat.format(report.startedAt)}',
                      ),
                      if (report.duration != null)
                        _SummaryRow(
                          label: 'Duration',
                          value: _formatDuration(report.duration!),
                        ),
                      _SummaryRow(
                        label: 'Responses',
                        value: '${report.responses.length} collected',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Responses Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Responses', style: AppTextStyles.heading3),
                      const SizedBox(height: AppSpacing.md),
                      if (report.responses.isEmpty)
                        Text(
                          'No responses recorded',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textLight,
                          ),
                        )
                      else
                        ...report.responses.entries.map((entry) {
                          return _ResponseRow(
                            fieldName: entry.key,
                            response: entry.value,
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds} seconds';
    } else if (duration.inHours < 1) {
      final mins = duration.inMinutes;
      final secs = duration.inSeconds % 60;
      return '$mins minute${mins == 1 ? '' : 's'} $secs second${secs == 1 ? '' : 's'}';
    } else {
      final hours = duration.inHours;
      final mins = duration.inMinutes % 60;
      return '$hours hour${hours == 1 ? '' : 's'} $mins minute${mins == 1 ? '' : 's'}';
    }
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.label,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseRow extends StatelessWidget {
  final String fieldName;
  final String response;

  const _ResponseRow({
    required this.fieldName,
    required this.response,
  });

  @override
  Widget build(BuildContext context) {
    // Convert snake_case or camelCase to Title Case
    final displayName = fieldName
        .replaceAllMapped(RegExp(r'_([a-z])'), (m) => ' ${m.group(1)!.toUpperCase()}')
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .trim()
        .split(' ')
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
        .join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppBorderRadius.small),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: AppTextStyles.label.copyWith(
              color: AppColors.dreamCloudBlue,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            response,
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }
}
