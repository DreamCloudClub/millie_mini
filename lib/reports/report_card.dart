import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/constants.dart';

/// Report card widget - taller than note cards with summary display
class ReportCard extends StatelessWidget {
  final Report report;
  final bool isSaved;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onSave;
  final VoidCallback? onRead;

  const ReportCard({
    super.key,
    required this.report,
    this.isSaved = false,
    required this.onOpen,
    this.onDelete,
    this.onSave,
    this.onRead,
  });

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(date);
    }
  }

  IconData _getCategoryIcon() {
    switch (report.category.toLowerCase()) {
      case 'technology':
      case 'tech':
        return Icons.computer;
      case 'weather':
        return Icons.cloud;
      case 'sports':
        return Icons.sports_soccer;
      case 'business':
      case 'finance':
        return Icons.trending_up;
      case 'entertainment':
        return Icons.movie;
      case 'science':
        return Icons.science;
      case 'health':
        return Icons.health_and_safety;
      case 'politics':
        return Icons.account_balance;
      default:
        return Icons.article;
    }
  }

  Color _getCategoryColor() {
    switch (report.category.toLowerCase()) {
      case 'technology':
      case 'tech':
        return Colors.blue;
      case 'weather':
        return Colors.cyan;
      case 'sports':
        return Colors.green;
      case 'business':
      case 'finance':
        return Colors.amber;
      case 'entertainment':
        return Colors.purple;
      case 'science':
        return Colors.teal;
      case 'health':
        return Colors.red;
      case 'politics':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: categoryColor.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Category icon + Title + Save button + Open button + Delete button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Category icon in colored circle
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getCategoryIcon(),
                    color: categoryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Title (expanded)
                Expanded(
                  child: Text(
                    report.title.isEmpty ? 'Untitled Report' : report.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Save/Unsave button (indicator + toggle)
                if (onSave != null) ...[
                  GestureDetector(
                    onTap: onSave,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSaved
                            ? Colors.green.withOpacity(0.3)
                            : Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_outline,
                        color: isSaved ? Colors.green : Colors.white.withOpacity(0.6),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                // Open button
                ElevatedButton(
                  onPressed: onOpen,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: categoryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    minimumSize: const Size(60, 36),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Open',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                // Delete button (if provided)
                if (onDelete != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Divider
            Container(
              height: 1,
              color: Colors.white.withOpacity(0.1),
            ),

            const SizedBox(height: AppSpacing.md),

            // Summary text (3-4 lines max)
            if (report.summary.isNotEmpty)
              Text(
                report.summary,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.4,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),

            const SizedBox(height: AppSpacing.md),

            // Footer: Category chip + Timestamp + Play button
            Row(
              children: [
                // Category chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    report.categoryLabel,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: categoryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Timestamp
                Text(
                  _formatRelativeTime(report.createdAt),
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const Spacer(),
                // Play button (bottom right)
                if (onRead != null)
                  GestureDetector(
                    onTap: onRead,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.volume_up,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
