import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../providers/reports_provider.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

/// Page for adding/editing announcement schedules
class ScheduleEditPage extends StatefulWidget {
  final CategorySchedule? schedule;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const ScheduleEditPage({
    super.key,
    this.schedule,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<ScheduleEditPage> createState() => _ScheduleEditPageState();
}

class _ScheduleEditPageState extends State<ScheduleEditPage> {
  late List<String> _selectedCategories;  // Empty = all categories
  late int _startTimeMinutes;
  late int _endTimeMinutes;
  late List<int> _daysOfWeek;
  late AnnouncementFrequency _frequency;
  late bool _enabled;
  bool _isSaving = false;

  bool get isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      _selectedCategories = List.from(widget.schedule!.categories);
      _startTimeMinutes = widget.schedule!.startTimeMinutes;
      _endTimeMinutes = widget.schedule!.endTimeMinutes;
      _daysOfWeek = List.from(widget.schedule!.daysOfWeek);
      _frequency = widget.schedule!.frequency;
      _enabled = widget.schedule!.enabled;
    } else {
      _selectedCategories = [];  // Empty = all categories
      _startTimeMinutes = 540; // 9:00 AM
      _endTimeMinutes = 1260; // 9:00 PM
      _daysOfWeek = [1, 2, 3, 4, 5, 6, 7]; // Every day
      _frequency = AnnouncementFrequency.minutes30;
      _enabled = true;
    }
  }

  TimeOfDay _minutesToTimeOfDay(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  int _timeOfDayToMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _minutesToTimeOfDay(_startTimeMinutes),
    );
    if (picked != null) {
      setState(() {
        _startTimeMinutes = _timeOfDayToMinutes(picked);
      });
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _minutesToTimeOfDay(_endTimeMinutes),
    );
    if (picked != null) {
      setState(() {
        _endTimeMinutes = _timeOfDayToMinutes(picked);
      });
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_daysOfWeek.contains(day)) {
        if (_daysOfWeek.length > 1) {
          _daysOfWeek.remove(day);
        }
      } else {
        _daysOfWeek.add(day);
        _daysOfWeek.sort();
      }
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No user logged in');
      }

      final provider = context.read<ReportsProvider>();

      if (isEditing) {
        final updated = widget.schedule!.copyWith(
          categories: _selectedCategories,
          startTimeMinutes: _startTimeMinutes,
          endTimeMinutes: _endTimeMinutes,
          daysOfWeek: _daysOfWeek,
          frequencyMinutes: _frequency.minutes,
          enabled: _enabled,
        );
        await provider.updateSchedule(updated);
      } else {
        final schedule = CategorySchedule.create(
          userId: userId,
          categories: _selectedCategories,
          startTimeMinutes: _startTimeMinutes,
          endTimeMinutes: _endTimeMinutes,
          daysOfWeek: _daysOfWeek,
          frequencyMinutes: _frequency.minutes,
          enabled: _enabled,
        );
        await provider.addSchedule(schedule);
      }

      widget.onSaved();
    } catch (e) {
      debugPrint('Error saving schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving schedule: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    if (!isEditing) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Schedule',
      message: 'This schedule will be permanently removed.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (!confirmed || !mounted) return;

    try {
      final provider = context.read<ReportsProvider>();
      await provider.deleteSchedule(widget.schedule!.id);
      widget.onSaved();
    } catch (e) {
      debugPrint('Error deleting schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting schedule: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatTime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    final period = hours >= 12 ? 'PM' : 'AM';
    final displayHour = hours > 12 ? hours - 12 : (hours == 0 ? 12 : hours);

    if (mins == 0) {
      return '$displayHour:00 $period';
    } else {
      return '$displayHour:${mins.toString().padLeft(2, '0')} $period';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            isEditing ? 'Edit Schedule' : 'Add Schedule',
            style: AppTextStyles.heading2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Main settings card
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppBorderRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category selector
                  _buildCategorySelector(),

                  const SizedBox(height: AppSpacing.lg),
                  const Divider(),
                  const SizedBox(height: AppSpacing.lg),

                  // Time range
                  const Text(
                    'Time Window',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildTimeRange(),

                  const SizedBox(height: AppSpacing.lg),
                  const Divider(),
                  const SizedBox(height: AppSpacing.lg),

                  // Days of week
                  const Text(
                    'Days',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildDaysSelector(),

                  const SizedBox(height: AppSpacing.lg),
                  const Divider(),
                  const SizedBox(height: AppSpacing.lg),

                  // Frequency
                  _buildFrequencySelector(),

                  const SizedBox(height: AppSpacing.lg),
                  const Divider(),
                  const SizedBox(height: AppSpacing.lg),

                  // Enable toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Enabled',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Transform.scale(
                        scale: 1.3,
                        child: Switch(
                          value: _enabled,
                          onChanged: (value) {
                            setState(() {
                              _enabled = value;
                            });
                          },
                          activeColor: AppColors.dreamCloudBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Save button
            AppButton(
              label: isEditing ? 'Save Changes' : 'Add Schedule',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
              isFullWidth: true,
              customColor: AppColors.dreamCloudBlue,
            ),

            // Delete button (only when editing)
            if (isEditing) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Delete Schedule',
                onPressed: _isSaving ? null : _delete,
                isFullWidth: true,
                customColor: AppColors.primaryOrange,
              ),
            ],

            // Bottom safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
        _selectedCategories.sort();
      }
    });
  }

  void _selectAllCategories() {
    setState(() {
      _selectedCategories.clear();
    });
  }

  Widget _buildCategorySelector() {
    return Consumer<ReportsProvider>(
      builder: (context, provider, _) {
        // Get user's enabled watchlist categories (main categories only)
        final enabledCategorySet = provider.enabledWatchlist
            .where((w) => w.subcategory == null)
            .map((w) => w.category)
            .toSet();

        // Order them according to the Report Categories list (groupedCategories order)
        final watchlistCategories = provider.groupedCategories.keys
            .where((cat) => enabledCategorySet.contains(cat))
            .toList();

        final isAllSelected = _selectedCategories.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Categories',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            if (watchlistCategories.isEmpty)
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
                        'No categories selected. Add categories in Report Categories above.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  // "All" chip
                  GestureDetector(
                    onTap: _selectAllCategories,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isAllSelected
                            ? AppColors.dreamCloudBlue
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'All',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isAllSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  // Individual category chips
                  ...watchlistCategories.map((category) {
                    final isSelected = _selectedCategories.contains(category);
                    return GestureDetector(
                      onTap: () => _toggleCategory(category),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.dreamCloudBlue
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _capitalize(category),
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildTimeRange() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _selectStartTime,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(AppBorderRadius.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(_startTimeMinutes),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Icon(Icons.arrow_forward, color: AppColors.textLight),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _selectEndTime,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(AppBorderRadius.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(_endTimeMinutes),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaysSelector() {
    const dayLabels = ['M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'];
    const dayValues = [1, 2, 3, 4, 5, 6, 7];

    return Column(
      children: [
        // Quick select buttons
        Row(
          children: [
            _buildQuickSelectButton(
              'Every day',
              [1, 2, 3, 4, 5, 6, 7],
            ),
            const SizedBox(width: AppSpacing.sm),
            _buildQuickSelectButton(
              'Weekdays',
              [1, 2, 3, 4, 5],
            ),
            const SizedBox(width: AppSpacing.sm),
            _buildQuickSelectButton(
              'Weekends',
              [6, 7],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Individual day toggles
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (index) {
            final day = dayValues[index];
            final isSelected = _daysOfWeek.contains(day);

            return GestureDetector(
              onTap: () => _toggleDay(day),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.dreamCloudBlue : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  dayLabels[index],
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildQuickSelectButton(String label, List<int> days) {
    final isSelected = _listEquals(_daysOfWeek, days);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _daysOfWeek = List.from(days);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.dreamCloudBlue.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(
              color: isSelected ? AppColors.dreamCloudBlue : AppColors.divider,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? AppColors.dreamCloudBlue : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sortedA = List<int>.from(a)..sort();
    final sortedB = List<int>.from(b)..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  Widget _buildFrequencySelector() {
    return AppDropdown<AnnouncementFrequency>(
      label: 'Frequency',
      value: _frequency,
      items: AnnouncementFrequency.values.map((freq) {
        return DropdownMenuItem(
          value: freq,
          child: Text(freq.displayName),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _frequency = value;
          });
        }
      },
    );
  }
}
