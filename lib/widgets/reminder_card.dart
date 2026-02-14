import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/constants.dart';

class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final bool useTriggeredTime;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onEdit,
    this.onDelete,
    this.useTriggeredTime = false,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat('EEEE').format(date); // Day name (Monday, Tuesday, etc.)
    }
  }

  String _formatDateNumber(DateTime date) {
    return DateFormat('MMM d').format(date); // "Jan 15"
  }

  String _formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date); // "3:00 PM"
  }

  String? _getReminderTime() {
    if (reminder.advanceNoticeMinutes != null) {
      final minutes = reminder.advanceNoticeMinutes!;
      if (minutes >= 60) {
        final hours = minutes ~/ 60;
        final remainingMinutes = minutes % 60;
        if (remainingMinutes > 0) {
          return '${hours}hr ${remainingMinutes}min';
        }
        return '${hours}hr';
      } else {
        return '${minutes}min';
      }
    }
    return null;
  }

  String? _getRecurrenceText() {
    if (reminder.recurrence != ReminderRecurrence.none) {
      return reminder.recurrence.displayName;
    }
    return null;
  }

  String? _getNotes() {
    // Check metadata for notes
    return reminder.metadata?['notes'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    // Use lastTriggeredAt for past alerts, scheduledAt for future alerts
    final mainAlertTime = useTriggeredTime && reminder.lastTriggeredAt != null
        ? reminder.lastTriggeredAt!
        : reminder.scheduledAt;
    final day = _formatDate(mainAlertTime);
    final dateStr = _formatDateNumber(mainAlertTime);
    final timeStr = _formatTime(mainAlertTime);
    final reminderTime = _getReminderTime();
    final notes = _getNotes();
    final hasNotes = notes != null && notes.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: Border.all(
          color: AppColors.dreamCloudBlue,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top padding
            const SizedBox(height: AppSpacing.lg),
            // Header row: Bell icon + Subject + Edit button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Bell icon in blue circle
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.dreamCloudBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Subject (expanded)
                Expanded(
                  child: Text(
                    reminder.title,
                    style: AppTextStyles.heading3.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Edit button
                OutlinedButton(
                  onPressed: onEdit,
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
                    minimumSize: const Size(60, 36),
                  ),
                  child: const Text(
                    'Edit',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                // Spacing between edit and delete buttons
                if (onDelete != null) const SizedBox(width: AppSpacing.sm),
                // Delete button (trash icon in faded orange circle) - same height as edit button
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 36,
                      height: 36, // Matches edit button height
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withValues(alpha: 0.7), // Slightly faded orange
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.delete, // Filled trash icon
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            // Bottom padding (matches top padding)
            const SizedBox(height: AppSpacing.lg),
            // Divider
            const Divider(
              color: AppColors.divider,
              thickness: 1,
              height: 0,
            ),
            // Padding below divider
            const SizedBox(height: AppSpacing.md),
            
            // Details section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First line: Day, Date, Time (includes AM/PM)
                Text(
                  '$day, $dateStr, $timeStr',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 16,
                  ),
                ),
                // Second line: Repeats and Reminder (if applicable)
                if (_getRecurrenceText() != null || reminderTime != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (_getRecurrenceText() != null) ...[
                        Text(
                          'Repeats: ${_getRecurrenceText()}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (reminderTime != null)
                          const SizedBox(width: AppSpacing.md),
                      ],
                      if (reminderTime != null)
                        Text(
                          'Reminder: $reminderTime',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            
            // Notes section (if notes exist)
            if (hasNotes) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Notes',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                notes,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            // Bottom padding
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
