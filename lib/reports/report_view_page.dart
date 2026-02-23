import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/voice_provider.dart';
import '../providers/reports_provider.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';

/// Full screen report view page
class ReportViewPage extends StatefulWidget {
  final Report report;
  final Function(Report) onReportUpdated;
  final VoidCallback onReportDeleted;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onExit;
  final bool autoPlay;

  const ReportViewPage({
    super.key,
    required this.report,
    required this.onReportUpdated,
    required this.onReportDeleted,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
    this.autoPlay = false,
  });

  @override
  State<ReportViewPage> createState() => _ReportViewPageState();
}

class _ReportViewPageState extends State<ReportViewPage> {
  late Report _currentReport;

  @override
  void initState() {
    super.initState();
    _currentReport = widget.report;

    // Auto-play if requested (from AI navigation)
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _readAloud();
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }

  String _formatExpiry(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.isNegative) {
      return 'Expired';
    } else if (difference.inHours < 1) {
      return 'Expires in ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'Expires in ${difference.inHours}h';
    } else {
      return 'Expires ${DateFormat('MMM d').format(date)}';
    }
  }

  Color _getCategoryColor() {
    switch (_currentReport.category.toLowerCase()) {
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

  Future<void> _toggleSave() async {
    final reportsProvider = context.read<ReportsProvider>();
    final isSaved = reportsProvider.isReportSaved(_currentReport.id);

    if (isSaved) {
      await reportsProvider.unsaveReport(_currentReport.id);
    } else {
      await reportsProvider.saveReport(_currentReport.id);
    }

    widget.onReportUpdated(_currentReport);
    setState(() {}); // Refresh UI
  }

  Future<void> _copyToNote() async {
    final reportsProvider = context.read<ReportsProvider>();
    final note = await reportsProvider.copyToNote(_currentReport.id);

    if (note != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied to note: ${note.title}'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to copy to note'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _readAloud() async {
    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.readReport(_currentReport);
  }

  Future<void> _deleteReport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.primaryOrange,
                  size: 32,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Title
              const Text(
                'Delete Report?',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Message
              Text(
                'This will remove this report. This cannot be undone.',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Delete button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final reportsProvider = context.read<ReportsProvider>();
      await reportsProvider.deleteReport(_currentReport.id);
      widget.onReportDeleted();
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor();

    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with centered title
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                height: 44,
                child: Stack(
                  children: [
                    // Title (absolutely centered on screen)
                    const Center(
                      child: Text(
                        'AI Report',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Back button (left)
                    Positioned(
                      left: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    // Right side buttons: Save + Delete
                    Positioned(
                      right: 0,
                      child: Consumer<ReportsProvider>(
                        builder: (context, reportsProvider, _) {
                          final isSaved = reportsProvider.isReportSaved(_currentReport.id);

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Save/Unsave button (green)
                              GestureDetector(
                                onTap: _toggleSave,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isSaved ? Icons.bookmark : Icons.bookmark_outline,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              // Delete button (orange)
                              GestureDetector(
                                onTap: _deleteReport,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryOrange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Report content in bordered container
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: categoryColor.withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Consumer<ReportsProvider>(
                      builder: (context, reportsProvider, _) {
                        final isSaved = reportsProvider.isReportSaved(_currentReport.id);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category chip
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: categoryColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _currentReport.category.toUpperCase(),
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 12,
                                    color: categoryColor,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.md),

                            // Title (centered)
                            Center(
                              child: Text(
                                _currentReport.title.isEmpty
                                    ? 'Untitled Report'
                                    : _currentReport.title,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                            const SizedBox(height: AppSpacing.sm),

                            // Timestamps (centered)
                            Center(
                              child: Text(
                                '${_formatDate(_currentReport.createdAt)} at ${_formatTime(_currentReport.createdAt)}',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ),

                            // Expiry or Saved badge
                            const SizedBox(height: AppSpacing.xs),
                            Center(
                              child: isSaved
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.bookmark,
                                            size: 14,
                                            color: Colors.green.shade400,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Saved',
                                            style: TextStyle(
                                              fontFamily: AppTextStyles.fontFamily,
                                              fontSize: 12,
                                              color: Colors.green.shade400,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Text(
                                      _formatExpiry(_currentReport.expiresAt),
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 12,
                                        color: _currentReport.isExpired
                                            ? Colors.red.withOpacity(0.7)
                                            : Colors.orange.withOpacity(0.7),
                                      ),
                                    ),
                            ),

                            const SizedBox(height: AppSpacing.lg),

                            // Divider line
                            Container(
                              height: 1,
                              color: Colors.white.withOpacity(0.1),
                            ),

                            const SizedBox(height: AppSpacing.lg),

                            // Summary (if different from content)
                            if (_currentReport.summary.isNotEmpty &&
                                _currentReport.summary != _currentReport.content) ...[
                              Text(
                                _currentReport.summary,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.9),
                                  fontStyle: FontStyle.italic,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Container(
                                height: 1,
                                color: Colors.white.withOpacity(0.1),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],

                            // Full content
                            Text(
                              _currentReport.content.isEmpty
                                  ? 'No content'
                                  : _currentReport.content,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 16,
                                color: _currentReport.content.isEmpty
                                    ? Colors.white.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.9),
                                height: 1.6,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // Status text
            Consumer<VoiceProvider>(
              builder: (context, voiceProvider, _) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  voiceProvider.state.statusText,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ),

            // Bottom control bar - Play reads this report
            ControlBar(
              onPause: widget.onPause,
              onPlay: _readAloud,
              onRefresh: widget.onRefresh,
              onExit: widget.onExit,
            ),
          ],
        ),
      ),
    );
  }
}
