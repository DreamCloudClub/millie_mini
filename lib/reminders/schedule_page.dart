import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../widgets/confirm_dialog.dart';
import '../face/control_bar.dart';
import 'edit_alert_page.dart';

/// Schedule mode toggle
enum ScheduleFilter {
  future,
  past,
}

/// Dark-themed Schedule page matching notes page style
class SchedulePage extends StatefulWidget {
  final VoidCallback onNavigateToFace;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onExit;

  const SchedulePage({
    super.key,
    required this.onNavigateToFace,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
  });

  @override
  State<SchedulePage> createState() => SchedulePageState();
}

class SchedulePageState extends State<SchedulePage> with AutomaticKeepAliveClientMixin {
  ScheduleFilter _filter = ScheduleFilter.future;
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
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  List<Reminder> _filterReminders(List<Reminder> reminders) {
    if (_searchQuery.isEmpty) return reminders;
    return reminders.where((reminder) {
      final titleMatch = reminder.title.toLowerCase().contains(_searchQuery);
      final notesMatch = reminder.metadata?['notes']?.toString().toLowerCase().contains(_searchQuery) ?? false;
      return titleMatch || notesMatch;
    }).toList();
  }

  /// Public method to refresh schedule list (called from AI navigation)
  void refreshSchedule() {
    debugPrint('SchedulePage: Refreshing schedule list');
    final reminderProvider = context.read<ReminderProvider>();
    reminderProvider.loadReminders();
  }

  Future<void> _handleDeleteReminder(BuildContext context, String reminderId) async {
    final reminderProvider = context.read<ReminderProvider>();
    final reminder = reminderProvider.getReminderById(reminderId);
    
    if (reminder == null) return;
    
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Alert',
      message: 'This will permanently delete "${reminder.title}". This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed && context.mounted) {
      final success = await reminderProvider.deleteReminder(reminderId);
      
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  void _createAlert() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EditAlertPage(
          reminderId: null, // null = create mode
          onBack: () => Navigator.pop(context),
          onSaved: () {
            Navigator.pop(context);
          },
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _editAlert(Reminder reminder) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EditAlertPage(
          reminderId: reminder.id,
          onBack: () => Navigator.pop(context),
          onSaved: () {
            Navigator.pop(context);
          },
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
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
                      'AI Schedule',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Create alert button (green square with +)
                  GestureDetector(
                    onTap: _createAlert,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Search bar
            Padding(
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
                              hintText: 'Search for alerts...',
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
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Past/Future filter toggle
            _buildFilterToggle(),
            
            const SizedBox(height: AppSpacing.sm),
            
            // Schedule list in bordered container
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
                    child: Consumer<ReminderProvider>(
                      builder: (context, reminderProvider, _) {
                        final futureReminders = reminderProvider.activeReminders;
                        final pastReminders = reminderProvider.getPastReminders();
                        final baseReminders = _filter == ScheduleFilter.past 
                            ? pastReminders 
                            : futureReminders;
                        final reminders = _filterReminders(baseReminders);

                        if (reminderProvider.isLoading) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryOrange,
                            ),
                          );
                        }

                        if (baseReminders.isEmpty) {
                          return _buildEmptyState();
                        }

                        if (reminders.isEmpty && _searchQuery.isNotEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 64,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'No matching alerts',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 16,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: reminders.length,
                          itemBuilder: (context, index) {
                            final reminder = reminders[index];
                            return _ScheduleCard(
                              reminder: reminder,
                              onTap: () => _editAlert(reminder),
                              onDelete: () => _handleDeleteReminder(context, reminder.id),
                              showTriggeredTime: _filter == ScheduleFilter.past,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            
            // Status text - always visible with symmetrical padding
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
                onPlay: widget.onPlay,
                onRefresh: widget.onRefresh,
                onExit: widget.onExit,
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
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _filter = ScheduleFilter.past),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _filter == ScheduleFilter.past 
                        ? Colors.blue 
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Past',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: _filter == ScheduleFilter.past 
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
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _filter = ScheduleFilter.future),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _filter == ScheduleFilter.future 
                        ? Colors.blue 
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Upcoming',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: _filter == ScheduleFilter.future 
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
    final isPast = _filter == ScheduleFilter.past;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPast ? Icons.history : Icons.notifications_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            isPast ? 'No Past Alerts' : 'No Upcoming Alerts',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isPast 
                ? 'Triggered alerts from the last 24 hours will appear here'
                : 'Tap the + button to create a new alert',
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

/// Dark-themed schedule card matching note card style
class _ScheduleCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool showTriggeredTime;

  const _ScheduleCard({
    required this.reminder,
    required this.onTap,
    required this.onDelete,
    this.showTriggeredTime = false,
  });

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final targetDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (targetDate == today) {
      return 'Today';
    } else if (targetDate == tomorrow) {
      return 'Tomorrow';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dateTime.month - 1]} ${dateTime.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayTime = showTriggeredTime && reminder.lastTriggeredAt != null
        ? reminder.lastTriggeredAt!
        : reminder.scheduledAt;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Icon + Title + Edit button + Delete button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Alert icon in grey circle (matching note card style)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Title (expanded)
                Expanded(
                  child: Text(
                    reminder.title.isEmpty ? 'Untitled Alert' : reminder.title,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Edit button (matching note card "Open" button style)
                ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue,
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
                    'Edit',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                // Delete button (matching note card style - orange circle)
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
            ),
            
            const SizedBox(height: AppSpacing.md),
            
            // Divider (matching note card)
            Container(
              height: 1,
              color: Colors.white.withOpacity(0.1),
            ),
            
            const SizedBox(height: AppSpacing.md),
            
            // Date/time info
            Text(
              '${_formatDate(displayTime)} at ${_formatTime(displayTime)}',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            
            // Recurrence info (if recurring)
            if (reminder.recurrence != ReminderRecurrence.none) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Repeats ${_getRecurrenceText(reminder.recurrence).toLowerCase()}',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
            
            // Notes (if available)
            if (reminder.metadata != null && 
                reminder.metadata!['notes'] != null &&
                (reminder.metadata!['notes'] as String).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Notes: ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    TextSpan(
                      text: reminder.metadata!['notes'] as String,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getRecurrenceText(ReminderRecurrence recurrence) {
    return recurrence.displayName;
  }
}

