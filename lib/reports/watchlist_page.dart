import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/reports_provider.dart';
import '../utils/constants.dart';

/// Watchlist settings page for managing research subjects
class WatchlistPage extends StatefulWidget {
  final VoidCallback onBack;

  const WatchlistPage({
    super.key,
    required this.onBack,
  });

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final TextEditingController _subjectController = TextEditingController();
  final FocusNode _subjectFocusNode = FocusNode();
  bool _isAdding = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _subjectFocusNode.dispose();
    super.dispose();
  }

  Future<void> _addSubject() async {
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) return;

    setState(() => _isAdding = true);

    final reportsProvider = context.read<ReportsProvider>();
    final success = await reportsProvider.addToWatchlist(subject);

    if (success) {
      _subjectController.clear();
      _subjectFocusNode.unfocus();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subject already in watchlist'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    setState(() => _isAdding = false);
  }

  Future<void> _removeSubject(String subject) async {
    final reportsProvider = context.read<ReportsProvider>();
    await reportsProvider.removeFromWatchlist(subject);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  // Back button (orange)
                  GestureDetector(
                    onTap: widget.onBack,
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
                  // Title (centered)
                  const Expanded(
                    child: Text(
                      'Watchlist',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Spacer to balance layout
                  const SizedBox(width: 44),
                ],
              ),
            ),

            // Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Add topics you want Bubble to research. Reports will be generated hourly for these subjects.',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Add subject input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  // Text field
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _subjectController,
                        focusNode: _subjectFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., Technology, Sports, Weather',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addSubject(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Add button
                  GestureDetector(
                    onTap: _isAdding ? null : _addSubject,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isAdding
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Watchlist items
            Expanded(
              child: Consumer<ReportsProvider>(
                builder: (context, reportsProvider, _) {
                  final watchlist = reportsProvider.watchlist;

                  if (watchlist.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No subjects yet',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Add topics above to start receiving reports',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    itemCount: watchlist.length,
                    itemBuilder: (context, index) {
                      final subject = watchlist[index];
                      return _WatchlistItem(
                        subject: subject,
                        onDelete: () => _removeSubject(subject),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistItem extends StatelessWidget {
  final String subject;
  final VoidCallback onDelete;

  const _WatchlistItem({
    required this.subject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          // Subject icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.tag,
              color: Colors.blue,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Subject text
          Expanded(
            child: Text(
              subject,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
          // Delete button
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                color: Colors.red.shade300,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
