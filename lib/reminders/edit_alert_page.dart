import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';
import '../widgets/confirm_dialog.dart';

class EditAlertPage extends StatefulWidget {
  final String? reminderId;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const EditAlertPage({
    super.key,
    this.reminderId,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<EditAlertPage> createState() => _EditAlertPageState();
}

class _EditAlertPageState extends State<EditAlertPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  TimeOfDay? _advanceReminderTime; // Time before the alert (hours:minutes before)
  ReminderRecurrence _recurrence = ReminderRecurrence.none;
  bool _hasAdvanceNotice = false;
  bool _isLoading = false;

  bool get isEditing => widget.reminderId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isEditing) {
        _loadReminder();
      } else {
        // Default to today at current time + 1 hour
        final now = DateTime.now();
        _selectedDate = DateTime(now.year, now.month, now.day);
        _selectedTime = TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)));
      }
    });
  }

  void _loadReminder() {
    final reminder = context.read<ReminderProvider>().getReminderById(widget.reminderId!);
    if (reminder != null) {
      setState(() {
        _titleController.text = reminder.title;
        
        // Use scheduledAt as the main alert time (what we display)
        _selectedDate = DateTime(
          reminder.scheduledAt.year,
          reminder.scheduledAt.month,
          reminder.scheduledAt.day,
        );
        _selectedTime = TimeOfDay.fromDateTime(reminder.scheduledAt);
        
        // Load advance reminder time if it exists
        if (reminder.advanceNoticeMinutes != null && reminder.advanceNoticeMinutes! > 0) {
          // Calculate advance reminder time by subtracting advanceNoticeMinutes from scheduledAt
          final advanceTime = reminder.scheduledAt.subtract(Duration(minutes: reminder.advanceNoticeMinutes!));
          _advanceReminderTime = TimeOfDay.fromDateTime(advanceTime);
          _hasAdvanceNotice = true;
        }
        
        _recurrence = reminder.recurrence;
        
        final notes = reminder.metadata?['notes'] as String?;
        if (notes != null) {
          _notesController.text = notes;
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _selectAdvanceReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _advanceReminderTime ?? TimeOfDay.fromDateTime(
        DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    if (picked != null) {
      setState(() {
        _advanceReminderTime = picked;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date and time'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final reminderProvider = context.read<ReminderProvider>();
      final agentProvider = context.read<AgentProvider>();
      final agent = agentProvider.activeAgent;
      final voice = agent?.voice ?? 'Alloy';

      // Build main alert date/time (scheduledAt is always the main alert time)
      final scheduledAt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      // Calculate advance notice in minutes if advance reminder is set
      int? advanceNoticeMinutes;
      
      if (_hasAdvanceNotice && _advanceReminderTime != null && _selectedDate != null) {
        // Create DateTime for advance reminder time
        final advanceReminderDateTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _advanceReminderTime!.hour,
          _advanceReminderTime!.minute,
        );
        
        // Calculate difference in minutes between advance reminder and main alert
        final difference = scheduledAt.difference(advanceReminderDateTime);
        advanceNoticeMinutes = difference.inMinutes;
        
        if (advanceNoticeMinutes <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Advance reminder time must be before the main alert time'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      if (isEditing) {
        // Update existing reminder
        final success = await reminderProvider.updateReminder(
          reminderId: widget.reminderId!,
          title: _titleController.text.trim(),
          scheduledAt: scheduledAt,
          eventTime: null,
          advanceNoticeMinutes: advanceNoticeMinutes,
          recurrence: _recurrence,
          notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        );

        if (!mounted) return;
        
        setState(() {
          _isLoading = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alert saved successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          widget.onSaved();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reminderProvider.error ?? 'Failed to save alert'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } else {
        // Create new reminder
        final reminder = await reminderProvider.createReminder(
          title: _titleController.text.trim(),
          scheduledAt: scheduledAt,
          eventTime: null,
          advanceNoticeMinutes: advanceNoticeMinutes,
          recurrence: _recurrence,
          notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          voice: voice,
        );

        if (!mounted) return;
        
        setState(() {
          _isLoading = false;
        });

        if (reminder != null) {
          // Re-fetch to ensure we have the latest data
          await reminderProvider.loadReminders();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Alert created successfully'),
                backgroundColor: AppColors.success,
              ),
            );
            widget.onSaved();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reminderProvider.error ?? 'Failed to create alert'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving alert: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Custom top bar matching notes edit page
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
                  const SizedBox(width: AppSpacing.md),
                  // Title
                  Text(
                    isEditing ? 'Edit Alert' : 'Create New Alert',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(AppBorderRadius.card),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                AppTextField(
                  label: 'Subject',
                  hint: 'Enter alert subject',
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  darkMode: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Subject is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                
                // Date
                InkWell(
                  onTap: _selectDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      suffixIcon: Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.7)),
                    ),
                    child: Text(
                      _selectedDate != null
                          ? DateFormat('EEEE, MMMM d, y').format(_selectedDate!)
                          : 'Select date',
                      style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                
                // Time
                InkWell(
                  onTap: _selectTime,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Time',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      suffixIcon: Icon(Icons.access_time, color: Colors.white.withOpacity(0.7)),
                    ),
                    child: Text(
                      _selectedTime != null
                          ? _selectedTime!.format(context)
                          : 'Select time',
                      style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                
                // Advance notice checkbox
                CheckboxListTile(
                  title: const Text(
                    'Set advance reminder',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: _hasAdvanceNotice,
                  checkColor: Colors.white,
                  activeColor: AppColors.dreamCloudBlue,
                  side: BorderSide(color: Colors.white.withOpacity(0.5)),
                  onChanged: (value) {
                    setState(() {
                      _hasAdvanceNotice = value ?? false;
                      if (!_hasAdvanceNotice) {
                        _advanceReminderTime = null;
                      }
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                
                // Advance reminder time (if advance notice enabled)
                if (_hasAdvanceNotice) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InkWell(
                    onTap: _selectAdvanceReminderTime,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Reminder Time',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        suffixIcon: Icon(Icons.access_time, color: Colors.white.withOpacity(0.7)),
                      ),
                      child: Text(
                        _advanceReminderTime != null
                            ? _advanceReminderTime!.format(context)
                            : 'Select reminder time',
                        style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _advanceReminderTime != null && _selectedDate != null && _selectedTime != null
                        ? _calculateAdvanceReminderText()
                        : 'Set the time you want to receive an early reminder',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white.withOpacity(0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                
                const SizedBox(height: AppSpacing.md),
                
                // Recurrence dropdown
                DropdownButtonFormField<ReminderRecurrence>(
                  value: _recurrence,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Recurrence',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                  ),
                  iconEnabledColor: Colors.white.withOpacity(0.7),
                  items: ReminderRecurrence.values.map((recurrence) {
                    return DropdownMenuItem(
                      value: recurrence,
                      child: Text(
                        recurrence.displayName,
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _recurrence = value;
                      });
                    }
                  },
                ),
                
                const SizedBox(height: AppSpacing.md),
                
                // Notes (optional)
                AppTextField(
                  label: 'Notes (optional)',
                  hint: 'Add any additional notes',
                  controller: _notesController,
                  maxLines: 4,
                  darkMode: true,
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Save button (sky blue pill)
                AppButton(
                  label: 'Save Alert',
                  onPressed: _isLoading ? null : _handleSave,
                  isLoading: _isLoading,
                  isFullWidth: true,
                  customColor: AppColors.dreamCloudBlue,
                ),
                
                // Delete Alert button (only show when editing)
                if (isEditing) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Delete Alert',
                    onPressed: _isLoading ? null : _handleDelete,
                    isFullWidth: true,
                    customColor: AppColors.primaryOrange,
                  ),
                ],
              ],
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
  
  Future<void> _handleDelete() async {
    if (!isEditing) return;

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
                'Delete Alert?',
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
                'This will permanently delete this alert. This cannot be undone.',
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
                  // Delete button (filled orange)
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
    ) ?? false;

    if (confirmed && mounted) {
      setState(() {
        _isLoading = true;
      });

      try {
        final reminderProvider = context.read<ReminderProvider>();
        final success = await reminderProvider.deleteReminder(widget.reminderId!);
        
        setState(() {
          _isLoading = false;
        });

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alert deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          widget.onSaved();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reminderProvider.error ?? 'Failed to delete alert'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting alert: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _calculateAdvanceReminderText() {
    if (_advanceReminderTime == null || _selectedDate == null || _selectedTime == null) {
      return '';
    }
    
    // Calculate the main alert time
    final mainAlertTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    
    // Calculate advance reminder time
    final advanceReminderDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _advanceReminderTime!.hour,
      _advanceReminderTime!.minute,
    );
    
    // Calculate difference
    final difference = mainAlertTime.difference(advanceReminderDateTime);
    final totalMinutes = difference.inMinutes;
    
    if (totalMinutes <= 0) {
      return '⚠ Reminder time must be before alert time';
    }
    
    String timeStr = _advanceReminderTime!.format(context);
    return 'Reminder at $timeStr';
  }
}

