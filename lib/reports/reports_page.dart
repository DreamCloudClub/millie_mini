import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/voice_provider.dart';
import '../providers/reports_provider.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';
import 'report_card.dart';
import 'report_view_page.dart';

/// Report filter mode toggle
enum ReportFilter {
  live,
  history,
  saved,
}

/// AI Reports page with list of reports
class ReportsPage extends StatefulWidget {
  final VoidCallback onNavigateToFace;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onExit;

  const ReportsPage({
    super.key,
    required this.onNavigateToFace,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
  });

  @override
  State<ReportsPage> createState() => ReportsPageState();
}

class ReportsPageState extends State<ReportsPage> with AutomaticKeepAliveClientMixin {
  ReportFilter _filter = ReportFilter.live;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
    // Load report categories on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportsProvider>().loadReportCategories();
      // Wire up callbacks
      final voiceProvider = context.read<VoiceProvider>();
      voiceProvider.onOpenAndPlayReport = _openReportAndPlay;
      voiceProvider.onOpenLink = _openLink;
    });
  }

  @override
  void dispose() {
    // Clear callbacks
    final voiceProvider = context.read<VoiceProvider>();
    voiceProvider.onOpenAndPlayReport = null;
    voiceProvider.onOpenLink = null;
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Called by AI when user wants to hear full report
  void _openReportAndPlay(String reportId) async {
    debugPrint('ReportsPage: Opening report $reportId for playback');

    // Note: We don't pause here - the ReportViewPage will handle stopping
    // any current audio before playing the report

    // Find the report
    final reportsProvider = context.read<ReportsProvider>();
    final report = reportsProvider.liveReports.firstWhere(
      (r) => r.id == reportId,
      orElse: () => reportsProvider.savedReports.firstWhere(
        (r) => r.id == reportId,
        orElse: () => throw Exception('Report not found'),
      ),
    );

    // Mark as announced
    if (!reportsProvider.isReportAnnounced(reportId)) {
      await reportsProvider.markAnnounced(reportId);
    }

    if (!mounted) return;

    // Navigate to report view and auto-play
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ReportViewPage(
          report: report,
          autoPlay: true, // Auto-play on load
          onReportUpdated: (updatedReport) {
            refreshReports();
          },
          onReportDeleted: () {
            refreshReports();
          },
          onPause: widget.onPause,
          onPlay: widget.onPlay,
          onRefresh: widget.onRefresh,
          onExit: widget.onExit,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  /// Called by AI to open an external link
  void _openLink(String url) async {
    debugPrint('ReportsPage: Opening link $url');
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  void _onFocusChanged() {
    // Focus changes trigger rebuild to check keyboard visibility
    setState(() {});
  }

  bool _isKeyboardVisible() {
    // Check if search field has focus - more reliable than MediaQuery in immersive mode
    return _searchFocusNode.hasFocus;
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  /// Filter reports by search query
  List<Report> _filterBySearch(List<Report> reports) {
    if (_searchQuery.isEmpty) return reports;

    final query = _searchQuery;
    return reports.where((report) {
      return report.title.toLowerCase().contains(query) ||
          report.summary.toLowerCase().contains(query) ||
          report.category.toLowerCase().contains(query) ||
          (report.subcategory?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  /// Public method to refresh reports list (called from AI navigation)
  void refreshReports() {
    debugPrint('ReportsPage: Refreshing reports list');
    final reportsProvider = context.read<ReportsProvider>();
    reportsProvider.loadReports();
    reportsProvider.loadReportCategories();
  }

  /// Public method to change report filter (Live, History, Saved) - called from AI
  void setFilter(ReportFilter filter) {
    debugPrint('ReportsPage: Setting filter to $filter');
    setState(() {
      _filter = filter;
    });
  }

  /// Public method to get current filter
  ReportFilter get currentFilter => _filter;

  /// Public method to set category filter - called from AI
  void setCategory(String? category) {
    debugPrint('ReportsPage: Setting category to $category');
    final reportsProvider = context.read<ReportsProvider>();
    if (category == null) {
      reportsProvider.selectAllCategories();
    } else {
      // Set just this one category
      reportsProvider.setCategoryFilters({category});
    }
  }

  /// Get current reports based on filter and category
  List<Report> getCurrentReports() {
    final reportsProvider = context.read<ReportsProvider>();
    List<Report> reports;
    switch (_filter) {
      case ReportFilter.live:
        reports = reportsProvider.filteredLiveReports;
        break;
      case ReportFilter.history:
        reports = reportsProvider.historyReports;
        break;
      case ReportFilter.saved:
        reports = reportsProvider.filteredSavedReports;
        break;
    }
    return _filterBySearch(reports);
  }

  void _openReport(Report report) async {
    // Mark as announced (moves to history) when opened
    final reportsProvider = context.read<ReportsProvider>();
    if (!reportsProvider.isReportAnnounced(report.id)) {
      await reportsProvider.markAnnounced(report.id);
    }

    if (!mounted) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ReportViewPage(
          report: report,
          onReportUpdated: (updatedReport) {
            // Refresh reports when coming back
            refreshReports();
          },
          onReportDeleted: () {
            refreshReports();
          },
          onPause: widget.onPause,
          onPlay: widget.onPlay,
          onRefresh: widget.onRefresh,
          onExit: widget.onExit,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _deleteReport(Report report) {
    showDialog(
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
                'This will permanently delete "${report.title.isEmpty ? 'Untitled Report' : report.title}". This cannot be undone.',
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
                  // Cancel button (outline)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
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
                  // Delete button (filled orange)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        final reportsProvider = context.read<ReportsProvider>();
                        await reportsProvider.deleteReport(report.id);
                      },
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
  }

  void _toggleSaveReport(Report report) async {
    final reportsProvider = context.read<ReportsProvider>();
    if (reportsProvider.isReportSaved(report.id)) {
      await reportsProvider.unsaveReport(report.id);
    } else {
      await reportsProvider.saveReport(report.id);
    }
  }

  void _readReport(Report report) async {
    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.readReport(report);
  }

  void _skipToNextReport(Report currentReport) {
    // Get current reports and find next one
    final reports = getCurrentReports();
    final currentIndex = reports.indexWhere((r) => r.id == currentReport.id);

    if (currentIndex >= 0 && currentIndex < reports.length - 1) {
      final nextReport = reports[currentIndex + 1];
      _openReport(nextReport);
    } else {
      // No more reports, show message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No more reports'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Handle Wake button - triggers report check-in asking if now is a good time
  void _onWakeForReports() async {
    final voiceProvider = context.read<VoiceProvider>();
    await voiceProvider.triggerReportCheckIn();
  }

  /// Refresh both AI session and reports feed
  Future<void> _refreshAll() async {
    // Refresh AI session
    widget.onRefresh();
    // Reload reports from database
    await context.read<ReportsProvider>().loadReports();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
                    onTap: widget.onNavigateToFace,
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
                      'AI Reports',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Sort button (green=newest, blue=oldest)
                  Consumer<ReportsProvider>(
                    builder: (context, provider, _) {
                      final newestFirst = provider.newestFirst;
                      return GestureDetector(
                        onTap: () => provider.toggleSortOrder(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: newestFirst ? Colors.green : Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            newestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Category tabs + sort label
            _buildCategoryTabsWithSortLabel(),

            const SizedBox(height: AppSpacing.sm),

            // Search bar
            _buildSearchBar(),

            const SizedBox(height: AppSpacing.sm),

            // Live/History/Saved filter toggle
            _buildFilterToggle(),

            const SizedBox(height: AppSpacing.sm),

            // Reports list in bordered container
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Consumer<ReportsProvider>(
                      builder: (context, reportsProvider, _) {
                        List<Report> reports;
                        switch (_filter) {
                          case ReportFilter.live:
                            reports = reportsProvider.filteredLiveReports;
                            break;
                          case ReportFilter.history:
                            reports = reportsProvider.historyReports;
                            break;
                          case ReportFilter.saved:
                            reports = reportsProvider.filteredSavedReports;
                            break;
                        }

                        // Apply search filter
                        reports = _filterBySearch(reports);

                        if (reportsProvider.isLoading) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryOrange,
                            ),
                          );
                        }

                        if (reports.isEmpty) {
                          return _buildEmptyState();
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: reports.length,
                          itemBuilder: (context, index) {
                            final report = reports[index];
                            final isSaved = reportsProvider.isReportSaved(report.id);
                            return ReportCard(
                              report: report,
                              isSaved: isSaved,
                              onOpen: () => _openReport(report),
                              onDelete: () => _deleteReport(report),
                              onSave: () => _toggleSaveReport(report),
                              onRead: () => _readReport(report),
                              onSkip: () => _skipToNextReport(report),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Status text
            Consumer<VoiceProvider>(
              builder: (context, voiceProvider, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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

            // Bottom control bar - hide when keyboard is visible
            if (!_isKeyboardVisible())
              ControlBar(
                onPause: widget.onPause,
                onPlay: _onWakeForReports,
                onRefresh: _refreshAll,
                onExit: widget.onExit,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabsWithSortLabel() {
    return Consumer<ReportsProvider>(
      builder: (context, provider, _) {
        // Use enabled watchlist categories (what user selected in settings)
        final categories = provider.enabledWatchlist
            .map((w) => w.category)
            .toSet()
            .toList();
        final isAllSelected = provider.isAllCategoriesSelected;
        final newestFirst = provider.newestFirst;

        return Row(
          children: [
            // Category tabs (scrollable, takes available space)
            Expanded(
              child: SizedBox(
                height: 40,
                child: categories.isEmpty
                    ? const SizedBox.shrink()
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: AppSpacing.md),
                        children: [
                          // "All" tab
                          _buildCategoryTab(
                            label: 'All',
                            isSelected: isAllSelected,
                            onTap: () => provider.selectAllCategories(),
                          ),
                          // Category tabs (multi-select)
                          ...categories.map((category) {
                            final displayName = category[0].toUpperCase() + category.substring(1);
                            final isSelected = provider.isCategoryFilterSelected(category);
                            return _buildCategoryTab(
                              label: displayName,
                              isSelected: isSelected,
                              onTap: () => provider.toggleCategoryFilter(category),
                              color: _getCategoryColor(category),
                            );
                          }),
                        ],
                      ),
              ),
            ),
            // Sort label (right justified)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Text(
                newestFirst ? 'Newest' : 'Oldest',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: newestFirst ? Colors.green : Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final tabColor = color ?? Colors.blue;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? tabColor : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            // Clear button (X)
            GestureDetector(
              onTap: _clearSearch,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Search field
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search for reports...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Search button
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search,
                color: Colors.black,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Live
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _filter = ReportFilter.live),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _filter == ReportFilter.live
                        ? Colors.blue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Live',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: _filter == ReportFilter.live
                            ? Colors.white
                            : Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // History
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _filter = ReportFilter.history),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _filter == ReportFilter.history
                        ? Colors.blue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'History',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: _filter == ReportFilter.history
                            ? Colors.white
                            : Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Saved
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _filter = ReportFilter.saved),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _filter == ReportFilter.saved
                        ? Colors.blue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Saved',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: _filter == ReportFilter.saved
                            ? Colors.white
                            : Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearchQuery = _searchQuery.isNotEmpty;

    IconData icon;
    String title;
    String subtitle;

    if (hasSearchQuery) {
      icon = Icons.search_off;
      title = 'No Results';
      subtitle = 'No reports match "$_searchQuery"';
    } else {
      switch (_filter) {
        case ReportFilter.live:
          icon = Icons.article_outlined;
          title = 'No Live Reports';
          subtitle = 'New reports will appear here';
          break;
        case ReportFilter.history:
          icon = Icons.history;
          title = 'No History';
          subtitle = 'Reports you\'ve opened will appear here';
          break;
        case ReportFilter.saved:
          icon = Icons.bookmark_outline;
          title = 'No Saved Reports';
          subtitle = 'Save reports to keep them permanently';
          break;
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
