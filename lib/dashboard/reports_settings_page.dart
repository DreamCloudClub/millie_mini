import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/reports_provider.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import 'schedule_edit_page.dart';

/// Settings page for AI Reports configuration
/// - Categories: what shows in the feed
/// - Schedules: when the robot speaks
class ReportsSettingsPage extends StatelessWidget {
  final VoidCallback onBack;

  const ReportsSettingsPage({
    super.key,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Reports Settings',
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Consumer<ReportsProvider>(
          builder: (context, provider, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Categories Card (for feed)
                _CategoriesCard(
                  groupedCategories: provider.groupedCategories,
                  watchlist: provider.watchlist,
                  onToggle: (category, subcategory, enabled) async {
                    // Get subcategories for this category
                    final subcategories = provider.groupedCategories[category]
                        ?.where((c) => c.subcategory != null)
                        .map((c) => c.subcategory!)
                        .toSet() ?? {};

                    if (enabled) {
                      // Unchecking
                      await provider.removeFromWatchlist(
                        category: category,
                        subcategory: subcategory,
                      );

                      // If unchecking main category, also remove all subcategories
                      if (subcategory == null) {
                        for (final sub in subcategories) {
                          await provider.removeFromWatchlist(
                            category: category,
                            subcategory: sub,
                          );
                        }
                      }
                    } else {
                      // Checking - add the item
                      await provider.addToWatchlist(
                        category: category,
                        subcategory: subcategory,
                      );

                      // If checking main category, also add all subcategories
                      if (subcategory == null) {
                        for (final sub in subcategories) {
                          await provider.addToWatchlist(
                            category: category,
                            subcategory: sub,
                          );
                        }
                      }
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Display Size Card
                _DisplaySizeCard(
                  displaySize: provider.displaySize,
                  onChanged: (size) => provider.updateDisplaySize(size),
                ),
                const SizedBox(height: AppSpacing.md),

                // Schedules Card (for verbal announcements)
                _SchedulesCard(
                  schedules: provider.schedules,
                  onAddSchedule: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            ScheduleEditPage(
                          onBack: () => Navigator.pop(context),
                          onSaved: () => Navigator.pop(context),
                        ),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                  onEditSchedule: (schedule) {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            ScheduleEditPage(
                          schedule: schedule,
                          onBack: () => Navigator.pop(context),
                          onSaved: () => Navigator.pop(context),
                        ),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                  onToggleSchedule: (scheduleId, enabled) {
                    provider.toggleSchedule(scheduleId, enabled);
                  },
                  onDeleteSchedule: (scheduleId) {
                    provider.deleteSchedule(scheduleId);
                  },
                ),

                // Bottom padding
                SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.lg),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Card for selecting report categories
class _CategoriesCard extends StatefulWidget {
  final Map<String, List<NewsCategory>> groupedCategories;
  final List<WatchlistItem> watchlist;
  final Function(String category, String? subcategory, bool currentlyEnabled) onToggle;

  const _CategoriesCard({
    required this.groupedCategories,
    required this.watchlist,
    required this.onToggle,
  });

  @override
  State<_CategoriesCard> createState() => _CategoriesCardState();
}

class _CategoriesCardState extends State<_CategoriesCard> {
  final Set<String> _expandedCategories = {};

  bool _isEnabled(String category, String? subcategory) {
    return widget.watchlist.any(
      (w) => w.category == category &&
          w.subcategory == subcategory &&
          w.enabled,
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'technology':
        return Icons.computer;
      case 'business':
        return Icons.business;
      case 'science':
        return Icons.science;
      case 'health':
        return Icons.health_and_safety;
      case 'sports':
        return Icons.sports_soccer;
      case 'entertainment':
        return Icons.movie;
      case 'politics':
        return Icons.account_balance;
      case 'weather':
        return Icons.cloud;
      case 'kids':
        return Icons.child_care;
      default:
        return Icons.article;
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.groupedCategories.keys.toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Categories',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Select categories to show in your feed',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Category list
          if (categories.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.textLight, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'Loading categories...',
                      style: AppTextStyles.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else
            ...categories.map((category) {
              final subcategories = widget.groupedCategories[category]!
                  .where((c) => c.subcategory != null)
                  .map((c) => c.subcategory!)
                  .toList();

              final isExpanded = _expandedCategories.contains(category);
              final categoryEnabled = _isEnabled(category, null);
              final hasSubcategories = subcategories.isNotEmpty;

              return Column(
                children: [
                  // Main category checkbox
                  CheckboxListTile(
                    value: categoryEnabled,
                    onChanged: (value) {
                      widget.onToggle(category, null, categoryEnabled);
                    },
                    title: Row(
                      children: [
                        Icon(
                          _getCategoryIcon(category),
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(_capitalize(category)),
                        if (hasSubcategories) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedCategories.remove(category);
                                } else {
                                  _expandedCategories.add(category);
                                }
                              });
                            },
                            child: Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: AppColors.textLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.dreamCloudBlue,
                  ),

                  // Subcategories (indented checkboxes)
                  if (isExpanded && hasSubcategories)
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: Column(
                        children: subcategories.map((sub) {
                          final isSubEnabled = _isEnabled(category, sub);
                          return CheckboxListTile(
                            value: isSubEnabled,
                            onChanged: (value) {
                              widget.onToggle(category, sub, isSubEnabled);
                            },
                            title: Text(
                              _capitalize(sub),
                              style: const TextStyle(fontSize: 14),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.dreamCloudBlue,
                            dense: true,
                          );
                        }).toList(),
                      ),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// Card for selecting display size (font size)
class _DisplaySizeCard extends StatelessWidget {
  final DisplaySize displaySize;
  final ValueChanged<DisplaySize> onChanged;

  const _DisplaySizeCard({
    required this.displaySize,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dropdown
          AppDropdown<DisplaySize>(
            label: 'Display Size',
            value: displaySize,
            items: DisplaySize.values
                .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text(d.displayName),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            displaySize == DisplaySize.large
                ? 'Larger text for easier reading.'
                : 'Standard text size.',
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Card for managing verbal announcement schedules
class _SchedulesCard extends StatelessWidget {
  final List<CategorySchedule> schedules;
  final VoidCallback onAddSchedule;
  final ValueChanged<CategorySchedule> onEditSchedule;
  final Function(String, bool) onToggleSchedule;
  final ValueChanged<String> onDeleteSchedule;

  const _SchedulesCard({
    required this.schedules,
    required this.onAddSchedule,
    required this.onEditSchedule,
    required this.onToggleSchedule,
    required this.onDeleteSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reports Schedule',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'When to announce reports',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAddSchedule,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dreamCloudBlue,
                    side: const BorderSide(color: AppColors.dreamCloudBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Schedules list
          if (schedules.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.textLight, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(
                      child: Text(
                        'No schedules set. Add one to get report announcements.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...schedules.map((schedule) => _ScheduleRow(
                  schedule: schedule,
                  onTap: () => onEditSchedule(schedule),
                  onToggle: (enabled) => onToggleSchedule(schedule.id, enabled),
                  onDelete: () => onDeleteSchedule(schedule.id),
                )),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final CategorySchedule schedule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _ScheduleRow({
    required this.schedule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            // Mic icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.mic,
                color: schedule.enabled ? AppColors.textPrimary : AppColors.textLight,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.timeRangeDisplay,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: schedule.enabled ? AppColors.textPrimary : AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${schedule.daysDisplay} • ${schedule.frequency.displayName}',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            // Toggle
            SizedBox(
              height: 36,
              child: Transform.scale(
                scale: 1.2,
                child: Switch(
                  value: schedule.enabled,
                  onChanged: onToggle,
                  activeColor: AppColors.dreamCloudBlue,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Edit pill button (matches Add button style)
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dreamCloudBlue,
                  side: const BorderSide(color: AppColors.dreamCloudBlue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Delete button - rounded square orange
            GestureDetector(
              onTap: () async {
                final confirmed = await ConfirmDialog.show(
                  context,
                  title: 'Delete Schedule',
                  message: 'This schedule will be permanently removed.',
                  confirmLabel: 'Delete',
                  cancelLabel: 'Cancel',
                  isDangerous: true,
                  confirmColor: AppColors.primaryOrange,
                );
                if (confirmed) {
                  onDelete();
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
