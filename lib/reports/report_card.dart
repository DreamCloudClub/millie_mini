import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/reports_provider.dart';
import '../providers/voice_provider.dart';
import '../utils/constants.dart';

/// Report card widget - horizontal layout with image on left
class ReportCard extends StatelessWidget {
  final Report report;
  final bool isSaved;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onSave;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;

  const ReportCard({
    super.key,
    required this.report,
    this.isSaved = false,
    required this.onOpen,
    this.onDelete,
    this.onSave,
    this.onPlay,
    this.onPause,
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
      case 'kids':
        return Icons.child_care;
      case 'lifestyle':
        return Icons.spa;
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
      case 'kids':
        return Colors.orange;
      case 'lifestyle':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor();
    final displaySize = context.watch<ReportsProvider>().displaySize;
    final isLarge = displaySize == DisplaySize.large;
    final hasImage = report.imageUrl != null && report.imageUrl!.isNotEmpty;

    // Calculate square image size (1/3 of screen width)
    final imageSize = MediaQuery.of(context).size.width * 0.33;

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        height: imageSize, // Card height matches image for square
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: categoryColor.withOpacity(0.6),
            width: 1,
          ),
        ),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: Square image
          SizedBox(
            width: imageSize,
            height: imageSize,
            child: Stack(
                children: [
                  // Image
                  if (hasImage)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          bottomLeft: Radius.circular(15),
                        ),
                        child: Image.network(
                          report.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: categoryColor.withOpacity(0.2),
                                child: Icon(
                                  _getCategoryIcon(),
                                  color: categoryColor,
                                  size: 40,
                                ),
                              ),
                        ),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          bottomLeft: Radius.circular(15),
                        ),
                        child: Container(
                          color: categoryColor.withOpacity(0.2),
                          child: Icon(
                            _getCategoryIcon(),
                            color: categoryColor,
                            size: 40,
                          ),
                        ),
                      ),
                    ),

                  // Category icon at top-left
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: categoryColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getCategoryIcon(),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right: Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      report.title.isEmpty ? 'Untitled Report' : report.title,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: isLarge ? 23 : 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    // Summary text
                    if (report.summary.isNotEmpty)
                      Expanded(
                        child: Text(
                          report.summary,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: isLarge ? 21 : 17,
                            color: Colors.white.withOpacity(0.7),
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    const SizedBox(height: AppSpacing.sm),

                    // Timestamp
                    Text(
                      _formatRelativeTime(report.publishedAt ?? report.createdAt),
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    // Bottom row: Category label (left) + Buttons (right)
                    Row(
                      children: [
                        // Category chip (left)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: categoryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            report.categoryLabel,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 10,
                              color: categoryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Play/Pause button (blue)
                        if (onPlay != null) ...[
                          Consumer<VoiceProvider>(
                            builder: (context, voiceProvider, _) {
                              final isThisPlaying = voiceProvider.currentPlayingReportId == report.id;
                              final isPaused = voiceProvider.isReportAudioPaused;
                              final showPause = isThisPlaying && !isPaused;

                              return GestureDetector(
                                onTap: showPause ? onPause : onPlay,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    showPause ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],

                        // Save button (green with white icon)
                        if (onSave != null) ...[
                          GestureDetector(
                            onTap: onSave,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                isSaved ? Icons.bookmark : Icons.bookmark_outline,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],

                        // Delete button (orange)
                        if (onDelete != null)
                          GestureDetector(
                            onTap: onDelete,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryOrange,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
