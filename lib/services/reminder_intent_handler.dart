import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/reminder_provider.dart';

/// Flow state for reminder intent handling
enum ReminderFlowState {
  none,              // Not in reminder flow
  selectingAction,   // "schedule an alert" → choosing create/edit
  creating,          // Creating new alert - collecting fields
  editing,           // Editing existing alert - identifying and modifying
}

/// Represents a step in the reminder creation/editing flow
class ReminderFlowStep {
  final String question;
  final String? fieldName;  // Which field we're collecting (e.g., 'subject', 'date')
  final bool required;
  
  ReminderFlowStep({
    required this.question,
    this.fieldName,
    this.required = true,
  });
}

/// Handler for voice-based reminder creation and editing
class ReminderIntentHandler {
  final ReminderProvider reminderProvider;
  
  ReminderFlowState _flowState = ReminderFlowState.none;
  ReminderFlowState get flowState => _flowState;
  
  // Creation flow state
  String? _pendingTitle;
  DateTime? _pendingScheduledAt;
  DateTime? _pendingDate; // Date portion (time set to 00:00:00)
  DateTime? _pendingTime; // Time portion (date set to 2000-01-01)
  DateTime? _pendingEventTime;
  DateTime? _pendingAdvanceReminderTime;
  int? _pendingAdvanceNoticeMinutes;  // Calculated from advance time
  ReminderRecurrence _pendingRecurrence = ReminderRecurrence.none;
  String? _pendingNotes;
  int _creationStepIndex = 0;
  
  // Edit flow state
  Reminder? _editingReminder;
  String? _pendingEditField;  // Which field is being edited
  dynamic _pendingEditValue;   // New value for the field
  
  ReminderIntentHandler(this.reminderProvider);
  
  /// Check if user input triggers reminder flow
  bool isTriggerPhrase(String userInput) {
    final lower = userInput.toLowerCase().trim();
    
    // Extract keywords from user input
    final keywords = _extractKeywords(lower);
    
    // Check if both "schedule" and "alert" keywords are present (or variations)
    final hasSchedule = lower.contains('schedule') || 
                       lower.contains('scheduled') ||
                       lower.contains('scheduling');
    
    final hasAlert = lower.contains('alert') || 
                    lower.contains('alerts') ||
                    lower.contains('reminder') ||
                    lower.contains('reminders');
    
    // Also check for action words that suggest managing alerts
    final hasAction = lower.contains('create') ||
                     lower.contains('edit') ||
                     lower.contains('update') ||
                     lower.contains('add') ||
                     lower.contains('change') ||
                     lower.contains('modify') ||
                     lower.contains('set') ||
                     lower.contains('manage');
    
    // Trigger if:
    // 1. Contains both schedule and alert keywords, OR
    // 2. Contains alert + action word (like "edit an alert"), OR
    // 3. Contains schedule + action word (like "schedule something")
    final shouldTrigger = (hasSchedule && hasAlert) ||
                         (hasAlert && hasAction) ||
                         (hasSchedule && hasAction && (lower.contains('alert') || lower.contains('reminder')));
    
    if (shouldTrigger) {
      debugPrint('Trigger phrase detected: "$userInput" (schedule: $hasSchedule, alert: $hasAlert, action: $hasAction)');
    }
    
    return shouldTrigger;
  }
  
  /// Check if we're currently in a reminder flow
  bool get isInFlow => _flowState != ReminderFlowState.none;
  
  /// Start the reminder flow (user said "schedule an alert")
  void startFlow() {
    _flowState = ReminderFlowState.selectingAction;
    _resetCreationState();
    _resetEditState();
    debugPrint('ReminderIntentHandler: Started reminder flow');
  }
  
  /// Reset to normal conversation
  void endFlow() {
    debugPrint('ReminderIntentHandler.endFlow: Ending flow (current state: $_flowState)');
    _flowState = ReminderFlowState.none;
    _resetCreationState();
    _resetEditState();
    debugPrint('ReminderIntentHandler.endFlow: Flow ended, state is now: $_flowState');
  }
  
  /// Process user input in the reminder flow context
  /// Returns the AI's response/question, or null if should continue normal flow
  Future<String?> processInput(String userInput, List<Reminder> existingReminders) async {
    // CRITICAL: If flow state is none, don't process anything - return null immediately
    if (_flowState == ReminderFlowState.none) {
      debugPrint('ReminderIntentHandler.processInput: Flow state is none, returning null (not processing: "$userInput")');
      // Double-check: if flow state is none but creation state wasn't reset, force reset
      if (_pendingTitle != null || _creationStepIndex > 0) {
        debugPrint('ReminderIntentHandler.processInput: WARNING - Flow state is none but creation state not reset, forcing reset');
        _resetCreationState();
      }
      return null; // Not in flow, continue normal conversation
    }
    
    debugPrint('ReminderIntentHandler.processInput: Processing input "$userInput" in flow state: $_flowState, step: $_creationStepIndex');
    
    // NO exit phrase checking during creation flow - user must manually stop
    
    switch (_flowState) {
      case ReminderFlowState.selectingAction:
        return await _handleActionSelection(userInput);
      
      case ReminderFlowState.creating:
        debugPrint('ReminderIntentHandler.processInput: In creating state, step=$_creationStepIndex, calling _handleCreationStep');
        debugPrint('ReminderIntentHandler.processInput: BEFORE - flowState=$_flowState, step=$_creationStepIndex, title=$_pendingTitle, scheduledAt=$_pendingScheduledAt');
        final response = await _handleCreationStep(userInput);
        debugPrint('ReminderIntentHandler.processInput: _handleCreationStep returned: "$response"');
        debugPrint('ReminderIntentHandler.processInput: AFTER - flowState=$_flowState, step=$_creationStepIndex, title=$_pendingTitle, scheduledAt=$_pendingScheduledAt');
        if (response == null || response.isEmpty) {
          debugPrint('ReminderIntentHandler.processInput: ERROR - Handler returned null/empty!');
        }
        return response;
      
      case ReminderFlowState.editing:
        return await _handleEditStep(userInput, existingReminders);
      
      case ReminderFlowState.none:
        return null;
    }
  }
  
  /// Handle action selection (create vs edit)
  Future<String> _handleActionSelection(String userInput) async {
    // First check if user wants to exit (quick exit if they didn't mean to trigger)
    if (_shouldExitFlow(userInput, excludeNoOnNotesStep: false)) {
      endFlow();
      return "Okay, no problem. Is there anything else I can help you with?";
    }
    
    final lower = userInput.toLowerCase().trim();
    debugPrint('Action selection - input: "$userInput", lower: "$lower"');
    
    // Extract keywords to help with matching (before checking trigger phrase)
    final keywords = _extractKeywords(lower);
    debugPrint('Action selection - keywords: $keywords');
    
    // Check for create OR new keywords (either one works)
    final hasCreate = lower.contains('create') || keywords.contains('create');
    final hasNew = lower.contains('new') || keywords.contains('new');
    final hasCreateIntent = hasCreate || hasNew;
    
    // Check for edit OR existing keywords (either one works)
    final hasEdit = lower.contains('edit') || keywords.contains('edit');
    final hasExisting = lower.contains('existing') || keywords.contains('existing');
    final hasEditIntent = hasEdit || hasExisting;
    
    debugPrint('Action selection - hasCreate: $hasCreate, hasNew: $hasNew, hasCreateIntent: $hasCreateIntent');
    debugPrint('Action selection - hasEdit: $hasEdit, hasExisting: $hasExisting, hasEditIntent: $hasEditIntent');
    
    // If we have clear create/edit intent, use it immediately (even if it matches trigger phrase)
    if (hasCreateIntent && !hasEditIntent) {
      // Clear create intent
      debugPrint('Action selection: Creating new alert');
      _flowState = ReminderFlowState.creating;
      _creationStepIndex = 0;
      return await _getCreationQuestion(0);
    } else if (hasEditIntent && !hasCreateIntent) {
      // Clear edit intent
      debugPrint('Action selection: Editing existing alert');
      _flowState = ReminderFlowState.editing;
      return "Which alert would you like to edit? You can tell me the subject or the time it's scheduled for.";
    } else if (hasCreateIntent && hasEditIntent) {
      // Ambiguous - ask for clarification
      return "I'm not sure - would you like to create a new alert or edit an existing one?";
    }
    
    // Only check if this is the trigger phrase itself if no create/edit keywords were found
    if (isTriggerPhrase(userInput)) {
      // User just said something like "schedule an alert" - ask them what they want to do
      return "Would you like to create a new alert or edit an existing one?";
    }
    
    // Didn't match create/edit or trigger phrase - if they said something unrelated, allow exit
    // Check for common "no" or exit phrases that suggest they don't want to do this
    if (lower == 'no' || lower == 'nope' || lower.contains('nevermind') || lower.contains('forget it')) {
      endFlow();
      return "Okay, no problem. What would you like to talk about?";
    }
    
    // Otherwise ask for clarification
    return "Would you like to create a new alert or edit an existing one?";
  }
  
  /// Get the question for current creation step
  Future<String> _getCreationQuestion(int stepIndex) async {
    switch (stepIndex) {
      case 0: // Subject
        return "What would you like this alert to say? Things like: call mom, or brush your teeth.";
      
      case 1: // Date
        return "When should I set the alert? For instance 'tomorrow' or 'December 15th'.";
      
      case 2: // Time
        return "What time should I set the alert?";
      
      case 3: // Notes
        return "Any notes you'd like to add to this reminder?";
      
      case 4: // Final confirmation (should not be called directly, only via confirmation handler)
        // This case should not be reached via _getCreationQuestion
        return "";
      
      default:
        // Ready to create
        return await _completeCreation();
    }
  }
  
  /// Check if user wants to exit the flow
  /// excludeNoOnNotesStep: if true, don't treat "no" as exit (for notes step where "no" means "no notes")
  bool _shouldExitFlow(String userInput, {bool excludeNoOnNotesStep = false}) {
    final lower = userInput.toLowerCase().trim();
    
    // Simple exit words (exact match)
    // BUT: "no" is only exit if NOT on notes step (where it means "no notes")
    if (!excludeNoOnNotesStep && lower == 'no') {
      return true;
    }
    
    // Other exit words (always exit)
    if (lower == 'nope' || 
        lower == 'nah' ||
        lower == 'cancel' ||
        lower == 'exit' ||
        lower == 'stop' ||
        lower == 'quit') {
      return true;
    }
    
    // Multi-word exit phrases (always exit)
    // Be specific to avoid false positives (e.g., "don't" alone shouldn't match)
    if (lower.contains('nevermind') || 
        lower.contains('never mind') ||
        lower == 'forget it' ||
        lower.contains('forget about it') ||
        lower.contains('forget this') ||
        lower.contains("don't do it") ||
        lower.contains("do not do it") ||
        lower.contains("don't want") ||
        lower.contains("do not want") ||
        lower == "that's okay" ||
        lower == "that is okay" ||
        lower == "that's fine" ||
        lower == "that is fine" ||
        lower.contains("skip it") ||
        lower.contains("skip this") ||
        lower == "back" ||
        lower.contains("go back") ||
        lower.contains("never mind")) {
      return true;
    }
    
    // Note: Removed "that's it", "done", "thank you", "thanks", "that's great" etc. from exit phrases
    // These can be valid responses during confirmation (e.g., "yes, that's great" or "yes, thank you")
    // "That's it" should NEVER be treated as exit - it's a confirmation phrase
    
    return false;
  }

  /// Handle a step in the creation flow - COMPLETE REBUILD
  Future<String> _handleCreationStep(String userInput) async {
    debugPrint('_handleCreationStep: START - step=$_creationStepIndex, input="$userInput"');
    debugPrint('_handleCreationStep: State - title: $_pendingTitle, scheduledAt: $_pendingScheduledAt, date: $_pendingDate');
    
    // Step 0: Get subject
    if (_creationStepIndex == 0) {
      final title = userInput.trim();
      if (title.isEmpty) {
        debugPrint('_handleCreationStep: Step 0 - Empty title, asking again');
        return "What should the alert say?";
      }
      _pendingTitle = title;
      _creationStepIndex = 1;
      debugPrint('_handleCreationStep: Step 0 - Subject="$title", SET step to 1');
      return "When should I set the alert?";
    }
    
    // Step 1: Get date and time
    if (_creationStepIndex == 1) {
      debugPrint('_handleCreationStep: Step 1 - Processing date/time input');
      // If we already have a date, this input is the time
      if (_pendingDate != null) {
        debugPrint('_handleCreationStep: Step 1 - We have date, parsing time');
        final timeResult = _parseTime(userInput);
        if (timeResult == null) {
          debugPrint('_handleCreationStep: Step 1 - Failed to parse time');
          return "I couldn't understand that time. What time?";
        }
        _pendingScheduledAt = DateTime(
          _pendingDate!.year,
          _pendingDate!.month,
          _pendingDate!.day,
          timeResult.hour,
          timeResult.minute,
        );
        _creationStepIndex = 2;
        debugPrint('_handleCreationStep: Step 1 - Date+time="$_pendingScheduledAt", SET step to 2');
        return "Any notes you'd like to add?";
      }
      
      // Try to parse date+time together
      debugPrint('_handleCreationStep: Step 1 - Trying to parse date+time together');
      try {
        final dateTimeResult = _parseDateTime(userInput);
        if (dateTimeResult != null) {
          _pendingScheduledAt = dateTimeResult;
          _creationStepIndex = 2;
          debugPrint('_handleCreationStep: Step 1 - Date+time="$dateTimeResult", SET step to 2');
          return "Any notes you'd like to add?";
        }
      } catch (e, stackTrace) {
        debugPrint('_handleCreationStep: Step 1 - Error parsing date+time: $e');
        debugPrint('_handleCreationStep: Stack trace: $stackTrace');
        // Continue to try other parsing methods
      }
      
      // Try to parse just date
      debugPrint('_handleCreationStep: Step 1 - Trying to parse just date');
      final dateResult = _parseDate(userInput);
      if (dateResult != null) {
        _pendingDate = dateResult;
        debugPrint('_handleCreationStep: Step 1 - Date="$dateResult", staying on step 1 to get time');
        return "What time?";
      }
      
      // Couldn't parse
      debugPrint('_handleCreationStep: Step 1 - Failed to parse anything');
      return "I couldn't understand that. Say things like 'tomorrow at noon' or '6 a.m. today'.";
    }
    
    // Step 2: Get notes, then create
    if (_creationStepIndex == 2) {
      debugPrint('_handleCreationStep: Step 2 - Processing notes input');
      final notesInput = userInput.trim();
      if (notesInput.isEmpty || notesInput.toLowerCase() == 'no' || notesInput.toLowerCase() == 'nope') {
        _pendingNotes = null;
      } else {
        _pendingNotes = notesInput;
      }
      
      // Validate we have everything
      if (_pendingTitle == null || _pendingTitle!.isEmpty) {
        debugPrint('_handleCreationStep: Step 2 - Missing title, ending flow');
        endFlow();
        return "I'm missing the alert subject. Let's start over.";
      }
      if (_pendingScheduledAt == null) {
        debugPrint('_handleCreationStep: Step 2 - Missing scheduledAt, ending flow');
        endFlow();
        return "I'm missing the date and time. Let's start over.";
      }
      
      // Create the reminder
      debugPrint('_handleCreationStep: Step 2 - All fields ready, creating reminder');
      return await _completeCreation();
    }
    
    // Should never reach here
    debugPrint('_handleCreationStep: ERROR - Reached default case, step=$_creationStepIndex');
    endFlow();
    return "Something went wrong. Let's start over.";
  }
  
  // Removed _showFinalConfirmation and _handleFinalConfirmation - no confirmation step needed
  
  /// Complete the creation and create the reminder
  Future<String> _completeCreation() async {
    debugPrint('_completeCreation called');
    debugPrint('_completeCreation: Current state:');
    debugPrint('  - _pendingTitle: $_pendingTitle');
    debugPrint('  - _pendingScheduledAt: $_pendingScheduledAt');
    debugPrint('  - _pendingNotes: $_pendingNotes');
    debugPrint('  - _pendingRecurrence: $_pendingRecurrence');
    debugPrint('  - _pendingAdvanceNoticeMinutes: $_pendingAdvanceNoticeMinutes');
    
    // Validate all required fields
    if (_pendingTitle == null || _pendingTitle!.isEmpty) {
      debugPrint('_completeCreation: ERROR - Title is null or empty');
      endFlow();
      return "I'm missing the alert subject. Let's start over.";
    }
    
    if (_pendingScheduledAt == null) {
      debugPrint('_completeCreation: ERROR - ScheduledAt is null');
      endFlow();
      return "I'm missing the date and time. Let's start over.";
    }
    
    try {
      debugPrint('_completeCreation: Creating reminder with title: $_pendingTitle, scheduledAt: $_pendingScheduledAt, notes: $_pendingNotes');
      debugPrint('_completeCreation: scheduledAt details - hour: ${_pendingScheduledAt!.hour}, minute: ${_pendingScheduledAt!.minute}, isUtc: ${_pendingScheduledAt!.isUtc}');
      debugPrint('_completeCreation: scheduledAt.toIso8601String(): ${_pendingScheduledAt!.toIso8601String()}');
      
      final formattedTime = _formatDateTime(_pendingScheduledAt!);
      debugPrint('_completeCreation: Formatted date/time: $formattedTime');
      
      // Store pending values before creating (in case endFlow() clears them)
      final reminderTitle = _pendingTitle!;
      final reminderScheduledAt = _pendingScheduledAt!;
      final reminderNotes = _pendingNotes;
      final reminderRecurrence = _pendingRecurrence;
      final reminderAdvanceNotice = _pendingAdvanceNoticeMinutes;
      
      debugPrint('_completeCreation: Stored values for reminder creation:');
      debugPrint('  - Title: $reminderTitle');
      debugPrint('  - ScheduledAt: $reminderScheduledAt');
      debugPrint('  - Notes: $reminderNotes');
      debugPrint('  - Recurrence: $reminderRecurrence');
      debugPrint('  - AdvanceNotice: $reminderAdvanceNotice');
      
      // Create the reminder first - await to ensure it completes before continuing
      debugPrint('_completeCreation: About to call reminderProvider.createReminder()');
      
      Reminder? createdReminder;
      try {
        createdReminder = await reminderProvider.createReminder(
          title: reminderTitle,
          scheduledAt: reminderScheduledAt,
          eventTime: null, // scheduledAt is the main alert time, eventTime is deprecated
          advanceNoticeMinutes: reminderAdvanceNotice,
          recurrence: reminderRecurrence,
          recurrenceEndDate: null, // Recurring alerts are always indefinite
          notes: reminderNotes,
        );
        
        debugPrint('_completeCreation: createReminder() completed');
      } catch (createError, createStack) {
        debugPrint('_completeCreation: EXCEPTION during createReminder(): $createError');
        debugPrint('_completeCreation: Stack trace: $createStack');
        endFlow();
        return "I'm sorry, there was an error creating your reminder: $createError";
      }
      
      debugPrint('_completeCreation: createReminder() returned: ${createdReminder != null ? "SUCCESS (id: ${createdReminder!.id})" : "NULL"}');
      
      if (createdReminder == null) {
        debugPrint('_completeCreation: Failed to create reminder (createReminder returned null)');
        // Check if there's an error message from the provider
        final errorMessage = reminderProvider.error ?? 'Unknown error';
        debugPrint('_completeCreation: ReminderProvider error: $errorMessage');
        endFlow(); // End flow even on error
        return "I'm sorry, there was an error creating your reminder: $errorMessage";
      }
      
      debugPrint('_completeCreation: Reminder created successfully: ${createdReminder.id}');
      debugPrint('_completeCreation: Verifying reminder was saved - checking reminderProvider.reminders list');
      
      // Verify the reminder is in the provider's list (double-check it was saved)
      final remindersList = reminderProvider.reminders;
      final foundReminder = remindersList.any((r) => r.id == createdReminder!.id);
      debugPrint('_completeCreation: Reminder found in provider list: $foundReminder (total reminders: ${remindersList.length})');
      
      if (!foundReminder) {
        debugPrint('_completeCreation: WARNING - Reminder was created but not found in provider list!');
        // Don't fail here - the reminder might still be saved in Supabase
      }
      
      // Build simple confirmation message
      final notesText = reminderNotes != null && reminderNotes.isNotEmpty 
          ? " Notes: $reminderNotes." 
          : "";
      
      final confirmation = "I've created your reminder: $reminderTitle on $formattedTime.$notesText";
      
      // End flow immediately - no follow-up questions
      endFlow();
      debugPrint('_completeCreation: Flow ended, reminder saved');
      
      return confirmation;
    } catch (e, stackTrace) {
      debugPrint('Error creating reminder: $e');
      debugPrint('Stack trace: $stackTrace');
      endFlow(); // End flow even on error to prevent getting stuck
      return "I'm sorry, there was an error creating your reminder. Please try again.";
    }
  }
  
  /// Handle a step in the edit flow
  Future<String> _handleEditStep(String userInput, List<Reminder> existingReminders) async {
    // If we haven't identified the reminder yet
    if (_editingReminder == null) {
      final matchedReminder = _findReminder(userInput, existingReminders);
      if (matchedReminder == null) {
        if (existingReminders.isEmpty) {
          return "You don't have any alerts to edit. Would you like to create one instead?";
        }
        return "I couldn't find that alert. Can you tell me the subject or time again? "
            "Here are your current alerts: ${existingReminders.take(3).map((r) => r.title).join(', ')}.";
      }
      
      _editingReminder = matchedReminder;
      return "I found your alert: ${matchedReminder.title} on ${_formatDateTime(matchedReminder.scheduledAt)}. "
          "What would you like to change? You can say the subject, date, time, recurrence, advance reminder, or notes.";
    }
    
    // If we're waiting for a new value for a field, apply the edit
    if (_pendingEditField != null) {
      return await _applyEdit(userInput);
    }
    
    // Check if user wants to save (response to "Would you like me to save it?")
    final lower = userInput.toLowerCase().trim();
    debugPrint('_handleEditStep: Processing input "$userInput" (lower: "$lower"), _pendingEditField: $_pendingEditField');
    
    // CRITICAL: Check for save/yes responses FIRST - before field identification
    // This handles responses to "Should I save the alert?"
    // Strip punctuation for more robust matching
    final cleanLower = lower.replaceAll(RegExp(r'[.,!?;:]'), '').trim();
    if (cleanLower == 'yes' || 
        cleanLower == 'yeah' || 
        cleanLower == 'yep' ||
        cleanLower == 'yup' ||
        cleanLower == 'save' ||
        cleanLower == 'save it' ||
        cleanLower.contains('save it') ||
        cleanLower == 'ok' ||
        cleanLower == 'okay' ||
        cleanLower == 'sure' ||
        cleanLower.contains('go ahead') ||
        (cleanLower.contains('please') && (cleanLower.contains('save') || cleanLower == 'yes please' || cleanLower == 'please yes')) ||
        cleanLower == 'do it' ||
        cleanLower.startsWith('yes') || // "yes", "yes please", "yes do it", etc.
        cleanLower == 'that\'s correct' ||
        cleanLower == 'thats correct' ||
        cleanLower == 'correct') {
      debugPrint('_handleEditStep: User confirmed save - exiting edit flow');
      endFlow();
      return "Your alert has been updated. Is there anything else I can help you with?";
    }
    
    // If they say "no" to saving, ask what else they want to change
    if (lower == 'no' || lower == 'nope' || lower == 'nah') {
      debugPrint('_handleEditStep: User said "no" to saving - asking what else to change');
      return "What else would you like to change? You can say the subject, date, time, recurrence, advance reminder, or notes.";
    }
    
    // Check for other exit phrases (cancel, nevermind, etc.)
    if (_shouldExitFlow(userInput, excludeNoOnNotesStep: false)) {
      debugPrint('_handleEditStep: Exit phrase from helper function - exiting edit flow');
      endFlow();
      return "Your alert has been updated. Is there anything else I can help you with?";
    }
    
    debugPrint('_handleEditStep: No save/exit phrase detected, proceeding to field identification');
    
    // Identify which field to edit
    // BUT: Skip field identification if this looks like a confirmation response
    // (e.g., "yes", "ok", "sure" - these should have been caught above, but double-check)
    if (cleanLower == 'yes' || cleanLower == 'ok' || cleanLower == 'okay' || cleanLower == 'sure' || 
        cleanLower == 'yeah' || cleanLower == 'yep' || cleanLower == 'yup') {
      // This should have been caught above, but if we get here, exit anyway
      debugPrint('_handleEditStep: Confirmation detected in field identification - exiting');
      endFlow();
      return "Your alert has been updated. Is there anything else I can help you with?";
    }
    
    String? fieldToEdit;
    
    if (lower.contains('subject') || lower.contains('title') || (lower.contains('what') && !lower.contains('change'))) {
      fieldToEdit = 'subject';
    } else if (lower.contains('date')) {
      fieldToEdit = 'date';
    } else if (lower.contains('time')) {
      fieldToEdit = 'time';
    } else if (lower.contains('recur') || lower.contains('repeat')) {
      fieldToEdit = 'recurrence';
    } else if (lower.contains('advance') || lower.contains('early') || lower.contains('before')) {
      fieldToEdit = 'advance';
    } else if (lower.contains('note')) {
      fieldToEdit = 'notes';
    }
    
    if (fieldToEdit == null) {
      // Try to infer from context - if they gave a date/time, assume that's what they want to change
      if (_parseDateTime(userInput) != null || _parseTime(userInput) != null) {
        fieldToEdit = 'date';
      } else if (_parseRecurrence(userInput) != ReminderRecurrence.none) {
        fieldToEdit = 'recurrence';
      } else {
        // User didn't specify a field - ask for clarification
        return "What would you like to change about this alert? You can say the subject, date, time, recurrence, advance reminder, or notes.";
      }
    }
    
    _pendingEditField = fieldToEdit;
    return _getEditQuestion(fieldToEdit);
  }
  
  /// Get the question for editing a specific field
  String _getEditQuestion(String field) {
    switch (field) {
      case 'subject':
        return "What should the new subject be?";
      case 'date':
        return "What should the new date and time be?";
      case 'time':
        return "What should the new time be?";
      case 'recurrence':
        return "How should it repeat? Daily, weekly, monthly, or just once?";
      case 'advance':
        return "What time should the advance reminder be?";
      case 'notes':
        return "What should the notes be? Say 'remove' if you want to delete them.";
      default:
        return "What would you like to change?";
    }
  }
  
  /// Apply the edit to the reminder
  Future<String> _applyEdit(String userInput) async {
    if (_editingReminder == null || _pendingEditField == null) {
      return "I'm not sure what to update. Let's start over.";
    }
    
    try {
      final reminder = _editingReminder!;
      String confirmationMessage;
      
      switch (_pendingEditField) {
        case 'subject':
          await reminderProvider.updateReminder(
            reminderId: reminder.id,
            title: userInput.trim(),
          );
          confirmationMessage = "I've updated the subject to '${userInput.trim()}'.";
        
        case 'date':
          final newDateTime = _parseDateTime(userInput);
          if (newDateTime == null) {
            return "I couldn't understand that date and time. Can you try again?";
          }
          await reminderProvider.updateReminder(
            reminderId: reminder.id,
            scheduledAt: newDateTime,
          );
          confirmationMessage = "I've updated the date and time to ${_formatDateTime(newDateTime)}.";
        
        case 'time':
          final newTime = _parseTime(userInput);
          if (newTime == null) {
            return "I couldn't understand that time. Can you try again?";
          }
          final newDateTime = DateTime(
            reminder.scheduledAt.year,
            reminder.scheduledAt.month,
            reminder.scheduledAt.day,
            newTime.hour,
            newTime.minute,
          );
          await reminderProvider.updateReminder(
            reminderId: reminder.id,
            scheduledAt: newDateTime,
          );
          confirmationMessage = "I've updated the time to ${_formatTime(newDateTime)}.";
        
        case 'recurrence':
          final newRecurrence = _parseRecurrence(userInput);
          await reminderProvider.updateReminder(
            reminderId: reminder.id,
            recurrence: newRecurrence,
          );
          confirmationMessage = "I've updated the recurrence to ${newRecurrence.displayName.toLowerCase()}.";
        
        case 'advance':
          if (userInput.toLowerCase().contains('no') || userInput.toLowerCase().contains("don't") || userInput.toLowerCase().contains('remove')) {
            await reminderProvider.updateReminder(
              reminderId: reminder.id,
              advanceNoticeMinutes: null,
            );
            confirmationMessage = "I've removed the advance reminder.";
          } else {
            final advanceTime = _parseTime(userInput);
            if (advanceTime == null) {
              return "I couldn't understand that time. Can you try again?";
            }
            final advanceDateTime = DateTime(
              reminder.scheduledAt.year,
              reminder.scheduledAt.month,
              reminder.scheduledAt.day,
              advanceTime.hour,
              advanceTime.minute,
            );
            final advanceMinutes = reminder.scheduledAt.difference(advanceDateTime).inMinutes;
            if (advanceMinutes <= 0) {
              return "The advance reminder time must be before the scheduled time. Can you try again?";
            }
            await reminderProvider.updateReminder(
              reminderId: reminder.id,
              advanceNoticeMinutes: advanceMinutes,
            );
            confirmationMessage = "I've updated the advance reminder time.";
          }
        
        case 'notes':
          if (userInput.toLowerCase().contains('remove') || userInput.toLowerCase().contains('delete')) {
            await reminderProvider.updateReminder(reminderId: reminder.id, notes: '');
            confirmationMessage = "I've removed the notes.";
          } else {
            await reminderProvider.updateReminder(reminderId: reminder.id, notes: userInput.trim());
            confirmationMessage = "I've updated the notes.";
          }
        
        default:
          _pendingEditField = null; // Clear field so we can try again
          return "I'm not sure what to update. What would you like to change?";
      }
      
      // Clear the pending field since we've applied the edit
      _pendingEditField = null;
      
      // Ask if they want to save
      return "$confirmationMessage Should I save the alert?";
    } catch (e) {
      debugPrint('Error updating reminder: $e');
      _pendingEditField = null; // Clear field on error
      return "I'm sorry, there was an error updating your reminder. Please try again.";
    }
  }
  
  // Helper methods for parsing user input
  
  Reminder? _findReminder(String userInput, List<Reminder> reminders) {
    final lower = userInput.toLowerCase().trim();
    
    // Try exact title match first (highest priority)
    Reminder? match;
    try {
      match = reminders.firstWhere((r) => r.title.toLowerCase().trim() == lower);
      debugPrint('Found exact title match: ${match.title}');
      return match;
    } catch (e) {
      // Not found, continue
    }
    
    // Try keyword-based matching (more flexible)
    final userKeywords = _extractKeywords(lower);
    debugPrint('User input keywords: $userKeywords');
    
    if (userKeywords.isNotEmpty) {
      // Score each reminder based on keyword overlap
      final matches = reminders.map((r) {
        final reminderKeywords = _extractKeywords(r.title.toLowerCase());
        final score = _calculateKeywordScore(userKeywords, reminderKeywords);
        return (reminder: r, score: score);
      }).toList();
      
      // Sort by score (highest first)
      matches.sort((a, b) => b.score.compareTo(a.score));
      
      // Return the best match if score is above threshold
      if (matches.isNotEmpty && matches.first.score >= 0.5) {
        debugPrint('Found keyword match: ${matches.first.reminder.title} (score: ${matches.first.score})');
        return matches.first.reminder;
      }
    }
    
    // Try partial title match (contains check)
    try {
      match = reminders.firstWhere((r) {
        final reminderTitle = r.title.toLowerCase();
        return reminderTitle.contains(lower) || lower.contains(reminderTitle);
      });
      debugPrint('Found partial title match: ${match.title}');
      return match;
    } catch (e) {
      // Not found, continue
    }
    
    // Try time match
    final inputTime = _parseTime(userInput);
    if (inputTime != null) {
      try {
        match = reminders.firstWhere((r) {
          return r.scheduledAt.hour == inputTime.hour && r.scheduledAt.minute == inputTime.minute;
        });
        debugPrint('Found time match: ${match.title}');
        return match;
      } catch (e) {
        // Not found, continue
      }
    }
    
    // Try date match
    final inputDate = _parseDate(userInput);
    if (inputDate != null) {
      try {
        match = reminders.firstWhere((r) {
          return r.scheduledAt.year == inputDate.year &&
                 r.scheduledAt.month == inputDate.month &&
                 r.scheduledAt.day == inputDate.day;
        });
        debugPrint('Found date match: ${match.title}');
        return match;
      } catch (e) {
        // Not found, continue
      }
    }
    
    debugPrint('No match found for: "$userInput"');
    return null;
  }
  
  /// Extract keywords from text (removes common stop words and normalizes)
  List<String> _extractKeywords(String text) {
    // Common stop words to ignore
    const stopWords = {
      'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
      'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'should',
      'could', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those',
      'i', 'you', 'he', 'she', 'it', 'we', 'they', 'my', 'your', 'his', 'her',
      'its', 'our', 'their', 'me', 'him', 'us', 'them', 'mine', 'yours',
      'hers', 'ours', 'theirs', 'some', 'any', 'all', 'each', 'every', 'both',
      'few', 'many', 'much', 'more', 'most', 'other', 'another', 'such', 'what',
      'which', 'who', 'whom', 'whose', 'where', 'when', 'why', 'how', 'about',
      'into', 'through', 'during', 'before', 'after', 'above', 'below', 'up',
      'down', 'out', 'off', 'over', 'under', 'again', 'further', 'then', 'once',
    };
    
    // Normalize text: remove punctuation, split into words
    final words = text
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Replace punctuation with space
        .split(RegExp(r'\s+')) // Split on whitespace
        .where((w) => w.isNotEmpty) // Remove empty strings
        .map((w) => w.toLowerCase()) // Lowercase
        .where((w) => !stopWords.contains(w)) // Remove stop words
        .map((w) => _normalizeWord(w)) // Normalize word forms (drinking -> drink)
        .where((w) => w.length > 1) // Remove single characters
        .toList();
    
    return words;
  }
  
  /// Normalize word to base form (simple stemming)
  String _normalizeWord(String word) {
    // Handle common word variations
    // Remove common suffixes (simple approach)
    if (word.endsWith('ing') && word.length > 5) {
      return word.substring(0, word.length - 3); // drinking -> drink
    }
    if (word.endsWith('ed') && word.length > 4) {
      return word.substring(0, word.length - 2); // walked -> walk
    }
    if (word.endsWith('er') && word.length > 4) {
      return word.substring(0, word.length - 2); // runner -> run (not perfect but helps)
    }
    if (word.endsWith('ly') && word.length > 4) {
      return word.substring(0, word.length - 2); // quickly -> quick
    }
    if (word.endsWith('es') && word.length > 3) {
      return word.substring(0, word.length - 2); // boxes -> box
    }
    if (word.endsWith('s') && word.length > 3) {
      return word.substring(0, word.length - 1); // cats -> cat
    }
    return word;
  }
  
  /// Calculate keyword match score between two keyword lists (0.0 to 1.0)
  double _calculateKeywordScore(List<String> userKeywords, List<String> reminderKeywords) {
    if (userKeywords.isEmpty || reminderKeywords.isEmpty) return 0.0;
    
    // Count matching keywords
    final userSet = userKeywords.toSet();
    final reminderSet = reminderKeywords.toSet();
    
    // Find intersection (matching keywords)
    final matches = userSet.intersection(reminderSet).length;
    
    // Calculate score: matches / max(user keywords, reminder keywords)
    // This gives higher score when there's good overlap
    final maxLength = userKeywords.length > reminderKeywords.length 
        ? userKeywords.length 
        : reminderKeywords.length;
    
    if (maxLength == 0) return 0.0;
    
    final score = matches / maxLength;
    
    // Bonus if all reminder keywords are matched (perfect match)
    if (matches == reminderKeywords.length && matches > 0) {
      return (score * 0.7) + 0.3; // Boost perfect matches
    }
    
    return score;
  }
  
  DateTime? _parseDateTime(String input) {
    final now = DateTime.now();
    final lower = input.toLowerCase().trim();
    debugPrint('_parseDateTime: Parsing "$input"');
    
    // First, try to extract time from phrases like "today at 11 a.m." or "tomorrow at 3pm"
    // Extract time portion by looking for "at [time]" pattern
    DateTime? extractedTime;
    // More flexible pattern: "at 11", "at 11am", "at 11 a.m.", "at 11:30", "at 11:30pm", etc.
    final atTimePattern = RegExp(r'\bat\s+((?:\d+(?:[:\s\.]\d+)?)\s*(?:[ap]\.?\s*m\.?)?|noon|midnight)', caseSensitive: false);
    final atMatch = atTimePattern.firstMatch(lower);
    if (atMatch != null) {
      final timeStr = atMatch.group(1)!.trim();
      debugPrint('_parseDateTime: Extracted time string from "at" pattern: "$timeStr"');
      extractedTime = _parseTime(timeStr);
      if (extractedTime != null) {
        debugPrint('_parseDateTime: Successfully parsed time from "at" pattern: ${extractedTime.hour}:${extractedTime.minute}');
      } else {
        debugPrint('_parseDateTime: Failed to parse extracted time string: "$timeStr"');
      }
    }
    
    // Try relative dates with time FIRST (before trying separate date/time parsing)
    if (lower.contains('tomorrow')) {
      final tomorrow = now.add(const Duration(days: 1));
      if (extractedTime != null) {
        final combined = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, extractedTime.hour, extractedTime.minute);
        debugPrint('_parseDateTime: Tomorrow with extracted time - combined: $combined');
        return combined;
      }
      // Try parsing time from full input
      final time = _parseTime(input);
      if (time != null) {
        final combined = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, time.hour, time.minute);
        debugPrint('_parseDateTime: Tomorrow with parsed time - combined: $combined');
        return combined;
      }
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);
    } else if (lower.contains('today')) {
      if (extractedTime != null) {
        final combined = DateTime(now.year, now.month, now.day, extractedTime.hour, extractedTime.minute);
        debugPrint('_parseDateTime: Today with extracted time - combined: $combined');
        return combined;
      }
      // Try parsing time from full input
      final time = _parseTime(input);
      if (time != null) {
        final combined = DateTime(now.year, now.month, now.day, time.hour, time.minute);
        debugPrint('_parseDateTime: Today with parsed time - combined: $combined');
        return combined;
      }
      // If "today" but no time parsed, return null (don't default)
      debugPrint('_parseDateTime: "Today" detected but no time could be parsed, returning null');
      return null;
    } else if (lower.contains('next week')) {
      final nextWeek = now.add(const Duration(days: 7));
      if (extractedTime != null) {
        final combined = DateTime(nextWeek.year, nextWeek.month, nextWeek.day, extractedTime.hour, extractedTime.minute);
        debugPrint('_parseDateTime: Next week with extracted time - combined: $combined');
        return combined;
      }
      final time = _parseTime(input);
      if (time != null) {
        final combined = DateTime(nextWeek.year, nextWeek.month, nextWeek.day, time.hour, time.minute);
        debugPrint('_parseDateTime: Next week with parsed time - combined: $combined');
        return combined;
      }
      return DateTime(nextWeek.year, nextWeek.month, nextWeek.day, 9, 0);
    }
    
    // Try to parse as separate date and time
    DateTime? result = _parseDate(input);
    DateTime? time = extractedTime ?? _parseTime(input);
    
    if (result != null && time != null) {
      // Combine date and time
      final combined = DateTime(result.year, result.month, result.day, time.hour, time.minute);
      debugPrint('_parseDateTime: Combined date and time - result: $result, time: $time (hour: ${time.hour}, minute: ${time.minute}), combined: $combined');
      return combined;
    } else if (result != null) {
      // Just a date, use current time or default to 9am
      return DateTime(result.year, result.month, result.day, 9, 0);
    } else if (time != null) {
      // Just a time, use today's date
      final combined = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      debugPrint('_parseDateTime: Just time provided - time: $time (hour: ${time.hour}, minute: ${time.minute}), now: $now, combined: $combined');
      return combined;
    }
    
    // Try to parse common patterns like "December 15th at 3pm"
    final patterns = [
      RegExp(r'(\w+)\s+(\d+)(?:st|nd|rd|th)?\s+at\s+(\d+):?(\d+)?\s*(am|pm)', caseSensitive: false),
      RegExp(r'(\w+)\s+(\d+)(?:st|nd|rd|th)?\s+at\s+(\d+)\s*(am|pm)', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        try {
          final monthName = match.group(1);
          final day = int.parse(match.group(2)!);
          final hour = int.parse(match.group(3)!);
          final minute = match.group(4) != null ? int.parse(match.group(4)!) : 0;
          final ampm = match.group(5)?.toLowerCase() ?? '';
          
          final month = _parseMonthName(monthName!);
          if (month != null) {
            var hour24 = hour;
            if (ampm == 'pm' && hour < 12) hour24 = hour + 12;
            if (ampm == 'am' && hour == 12) hour24 = 0;
            
            final currentYear = now.year;
            return DateTime(currentYear, month, day, hour24, minute);
          }
        } catch (e) {
          debugPrint('Error parsing date pattern: $e');
        }
      }
    }
    
    return null;
  }
  
  DateTime? _parseDate(String input) {
    final now = DateTime.now();
    final lower = input.toLowerCase().trim();
    
    // Handle relative dates
    if (lower.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    } else if (lower.contains('tomorrow')) {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    } else if (lower.contains('yesterday')) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    }
    
    // Try to parse weekday names
    final weekdays = {
      'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
      'friday': 5, 'saturday': 6, 'sunday': 7
    };
    
    for (final entry in weekdays.entries) {
      if (lower.contains(entry.key)) {
        final targetDay = entry.value;
        final currentDay = now.weekday;
        var daysToAdd = targetDay - currentDay;
        if (daysToAdd <= 0) daysToAdd += 7; // Next occurrence
        final targetDate = now.add(Duration(days: daysToAdd));
        return DateTime(targetDate.year, targetDate.month, targetDate.day);
      }
    }
    
    // Try to parse month names (e.g., "December 15th", "Dec 15")
    final monthPattern = RegExp(r'(\w+)\s+(\d+)(?:st|nd|rd|th)?', caseSensitive: false);
    final match = monthPattern.firstMatch(lower);
    if (match != null) {
      try {
        final monthName = match.group(1);
        final day = int.parse(match.group(2)!);
        final month = _parseMonthName(monthName!);
        
        if (month != null) {
          final currentYear = now.year;
          // If the date is in the past this year, assume next year
          final candidate = DateTime(currentYear, month, day);
          if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
            return DateTime(currentYear + 1, month, day);
          }
          return candidate;
        }
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }
    
    return null;
  }
  
  DateTime? _parseTime(String input) {
    final lower = input.toLowerCase().trim();
    debugPrint('Parsing time from: "$input"');
    
    // Handle special times first: "noon", "midnight"
    if (lower.contains('noon') || (lower.contains('12') && lower.contains('pm')) || 
        (lower == '12 pm' || lower == '12:00 pm' || lower == '12:00pm')) {
      debugPrint('Parsed as noon (12:00 PM)');
      return DateTime(2000, 1, 1, 12, 0);
    }
    if (lower.contains('midnight') || (lower.contains('12') && lower.contains('am') && !lower.contains('noon')) ||
        (lower == '12 am' || lower == '12:00 am' || lower == '12:00am')) {
      debugPrint('Parsed as midnight (12:00 AM)');
      return DateTime(2000, 1, 1, 0, 0);
    }
    
    // Check for am/pm in original input first (before normalization removes it)
    // Use more flexible patterns to catch variations
    final hasAM = RegExp(r'\ba\.?m\.?', caseSensitive: false).hasMatch(lower);
    final hasPM = RegExp(r'\bp\.?m\.?', caseSensitive: false).hasMatch(lower);
    
    debugPrint('Detected AM: $hasAM, PM: $hasPM');
    
    // Convert written numbers to digits (e.g., "three" -> "3")
    final numberWords = {
      'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
      'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
      'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14',
      'fifteen': '15', 'sixteen': '16', 'seventeen': '17', 'eighteen': '18',
      'nineteen': '19', 'twenty': '20', 'thirty': '30'
    };
    
    String normalized = lower;
    for (final entry in numberWords.entries) {
      normalized = normalized.replaceAll(RegExp('\\b${entry.key}\\b'), entry.value);
    }
    
    // Normalize "o'clock", "oclock"
    normalized = normalized.replaceAll(RegExp(r"o['\s]*clock"), '');
    
    // Normalize am/pm variations to consistent format: "am" or "pm"
    // Handle "a.m.", "a m", "am", etc. -> "am"
    // Use replaceAllMapped to preserve the structure better
    normalized = normalized.replaceAllMapped(RegExp(r'\b(a\.?\s*m\.?|A\.?\s*M\.?)\b', caseSensitive: false), (match) => 'am');
    normalized = normalized.replaceAllMapped(RegExp(r'\b(p\.?\s*m\.?|P\.?\s*M\.?)\b', caseSensitive: false), (match) => 'pm');
    
    // Normalize spaces - collapse multiple spaces to single space, but preserve single spaces
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Strip trailing punctuation (periods, commas) that might interfere with parsing
    normalized = normalized.replaceAll(RegExp(r'[.,;:]+$'), '').trim();
    
    debugPrint('Normalized time string: "$normalized" (original: "$input", hasAM: $hasAM, hasPM: $hasPM)');
    
    // Handle decimal-like times (e.g., "7.48" from "seven forty-eight" should be "7:48")
    // This is a common STT issue where spoken times become decimals
    // Check for decimal format BEFORE we normalize am/pm away
    if (RegExp(r'^\d+\.\d+').hasMatch(normalized)) {
      final decimalMatch = RegExp(r'^(\d+)\.(\d+)(.*)$').firstMatch(normalized);
      if (decimalMatch != null) {
        final hour = int.tryParse(decimalMatch.group(1)!);
        final minuteStr = decimalMatch.group(2)!;
        final rest = decimalMatch.group(3) ?? '';
        
        // Check if am/pm is in the rest of the string
        final hasAMinRest = RegExp(r'\bam\b', caseSensitive: false).hasMatch(rest);
        final hasPMinRest = RegExp(r'\bpm\b', caseSensitive: false).hasMatch(rest);
        final effectiveAM = hasAM || hasAMinRest;
        final effectivePM = hasPM || hasPMinRest;
        
        if (hour != null && minuteStr.length == 2) {
          final minute = int.tryParse(minuteStr);
          if (minute != null && minute <= 59) {
            var adjustedHour = hour;
            
            // Apply AM/PM conversion
            if (effectivePM && hour < 12) {
              adjustedHour = hour + 12;
            } else if (effectiveAM && hour == 12) {
              adjustedHour = 0;
            } else if (effectiveAM && hour > 12) {
              // Invalid - skip this format
              debugPrint('Invalid: hour $hour with AM');
            } else if (!effectiveAM && !effectivePM && hour <= 12) {
              // No am/pm specified for 12-hour format, assume AM
              adjustedHour = hour == 12 ? 0 : hour;
            }
            
            if (adjustedHour <= 23) {
              debugPrint('Parsed decimal time "$normalized" as: $adjustedHour:$minute (AM: $effectiveAM, PM: $effectivePM)');
              return DateTime(2000, 1, 1, adjustedHour, minute);
            }
          }
        }
      }
    }
    
    // Pattern for "3pm", "3:30pm", "3 PM", "15:30", "3 30 pm", etc.
    // Order matters: more specific patterns (with minutes) must come first
    final timePatterns = [
      // "7:42am" or "3:30pm" (colon with am/pm, no space)
      RegExp(r'^(\d+):(\d+)(am|pm)\b', caseSensitive: false),
      // "7:42 am" or "3:30 pm" (colon with am/pm, with space)
      RegExp(r'^(\d+):(\d+)\s+(am|pm)\b', caseSensitive: false),
      // "7 42am" or "3 30pm" (spaced, with am/pm, no space before am/pm)
      RegExp(r'^(\d+)\s+(\d+)(am|pm)\b', caseSensitive: false),
      // "7 42 am" or "3 30 pm" (spaced, with am/pm, with space)
      RegExp(r'^(\d+)\s+(\d+)\s+(am|pm)\b', caseSensitive: false),
      // "7.48am" or "3.30pm" (decimal from STT, with am/pm, no space)
      RegExp(r'^(\d+)\.(\d+)(am|pm)\b', caseSensitive: false),
      // "7.48 am" or "3.30 pm" (decimal from STT, with am/pm, with space)
      RegExp(r'^(\d+)\.(\d+)\s+(am|pm)\b', caseSensitive: false),
      // "15:30" (24-hour format with colon)
      RegExp(r'^(\d+):(\d+)$'),
      // "15 30" (24-hour format without colon)
      RegExp(r'^(\d+)\s+(\d+)$'),
      // "3 pm" or "1 pm" (no minutes, with am/pm, with space)
      RegExp(r'^(\d+)\s+(am|pm)\b', caseSensitive: false),
      // "3pm" or "1pm" (no minutes, with am/pm, no space)
      RegExp(r'^(\d+)(am|pm)\b', caseSensitive: false),
      // Just a number (will use hasAM/hasPM context)
      RegExp(r'^(\d+)$'),
    ];
    
    for (int i = 0; i < timePatterns.length; i++) {
      final pattern = timePatterns[i];
      debugPrint('Trying pattern ${i + 1}: ${pattern.pattern}');
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        final groupCount = match.groupCount;
        debugPrint('Pattern ${i + 1} matched! Groups: $groupCount');
        try {
          final hourStr = match.group(1);
          
          // Determine which groups are hour, minute, and am/pm based on pattern index
          String? minuteStr;
          String? ampm;
          
          if (i < 6) {
            // Patterns 0-5: hour:minute(am|pm) - groups are [hour, minute, ampm]
            minuteStr = groupCount >= 2 ? match.group(2) : null;
            ampm = groupCount >= 3 ? match.group(3)?.toLowerCase() : null;
          } else if (i == 6 || i == 7) {
            // Patterns 7-8: hour:minute (24-hour, no am/pm) - groups are [hour, minute]
            minuteStr = groupCount >= 2 ? match.group(2) : null;
            ampm = null;
          } else if (i == 8) {
            // Pattern 9: hour am/pm (no minutes) - groups are [hour, ampm]
            minuteStr = null; // No minutes in this pattern
            ampm = groupCount >= 2 ? match.group(2)?.toLowerCase() : null;
          } else if (i == 9) {
            // Pattern 10: hour(am|pm) (no space, no minutes) - groups are [hour, ampm]
            minuteStr = null; // No minutes in this pattern
            ampm = groupCount >= 2 ? match.group(2)?.toLowerCase() : null;
          } else {
            // Pattern 11: just hour (no minutes, no am/pm) - groups are [hour]
            minuteStr = null;
            ampm = null;
          }
          
          debugPrint('Pattern ${i + 1} extracted - hourStr: "$hourStr", minuteStr: "$minuteStr", ampm: "$ampm"');
          
          // If no am/pm in pattern but we detected it earlier, use that
          if (ampm == null) {
            if (hasPM) {
              ampm = 'pm';
              debugPrint('Using hasPM context for ampm: pm');
            } else if (hasAM) {
              ampm = 'am';
              debugPrint('Using hasAM context for ampm: am');
            }
          }
          
          if (hourStr != null) {
            var hour = int.parse(hourStr);
            final minute = minuteStr != null ? int.parse(minuteStr) : 0;
            
            debugPrint('Parsed hour: $hour, minute: $minute, ampm: $ampm');
            
            // Validate minute range
            if (minute > 59) {
              debugPrint('Invalid minutes: $minute, trying next pattern');
              continue; // Try next pattern
            }
            
            // Validate hour range before AM/PM conversion
            // If we have am/pm, it must be 12-hour format (1-12)
            // If no am/pm, it could be 24-hour format (0-23)
            if (ampm != null && (hour < 1 || hour > 12)) {
              debugPrint('Invalid hour for 12-hour format: $hour (with ampm: $ampm), trying next pattern');
              continue;
            }
            
            // Handle AM/PM
            if (ampm != null) {
              var originalHour = hour;
              if (ampm == 'pm' && hour < 12) {
                hour += 12;
              } else if (ampm == 'am' && hour == 12) {
                hour = 0;
              } else if (ampm == 'am' && hour > 12) {
                // Invalid - can't have hour > 12 with AM
                debugPrint('Invalid hour with AM: $hour, trying next pattern');
                continue;
              }
              debugPrint('AM/PM conversion: $originalHour $ampm -> $hour (24-hour format)');
            } else {
              // No am/pm specified - use context if available, otherwise assume 24-hour if > 12
              if (hour <= 12) {
                // Could be AM or PM - but if > 12 it's definitely 24-hour
                // For ambiguity, we'll assume it's valid 24-hour if <= 23
                if (hour > 23) {
                  debugPrint('Invalid 24-hour format hour: $hour, trying next pattern');
                  continue;
                }
              }
            }
            
            // Final validation
            if (hour < 0 || hour > 23) {
              debugPrint('Final hour validation failed: $hour, trying next pattern');
              continue;
            }
            
            debugPrint('Successfully parsed time: $hour:$minute (pattern ${i + 1}, original hour: $hourStr, ampm: $ampm)');
            return DateTime(2000, 1, 1, hour, minute); // Use dummy date, we only care about time
          }
        } catch (e, stackTrace) {
          debugPrint('Error parsing time with pattern ${i + 1}: $e');
          debugPrint('Stack trace: $stackTrace');
        }
      } else {
        debugPrint('Pattern ${i + 1} did not match');
      }
    }
    
    debugPrint('Failed to parse time from: "$input"');
    return null;
  }
  
  int? _parseMonthName(String monthName) {
    final months = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9, 'sept': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };
    
    return months[monthName.toLowerCase()];
  }
  
  ReminderRecurrence _parseRecurrence(String input) {
    final lower = input.toLowerCase();
    if (lower.contains('daily') || lower.contains('every day')) {
      return ReminderRecurrence.daily;
    } else if (lower.contains('weekly') || lower.contains('every week')) {
      return ReminderRecurrence.weekly;
    } else if (lower.contains('monthly') || lower.contains('every month')) {
      return ReminderRecurrence.monthly;
    }
    return ReminderRecurrence.none;
  }
  
  String _formatDateTime(DateTime dt) {
    // Ensure we're using local time for both date and time parts
    // Log the original DateTime to debug timezone issues
    debugPrint('_formatDateTime: Input dt: $dt (isUtc: ${dt.isUtc}, timeZoneName: ${dt.timeZoneName})');
    final localDt = dt.isUtc ? dt.toLocal() : dt;
    debugPrint('_formatDateTime: Converted to local: $localDt (timeZoneName: ${localDt.timeZoneName})');
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    final day = localDt.day;
    final suffix = _getDaySuffix(day);
    final formatted = '${monthNames[localDt.month - 1]} ${day}$suffix at ${_formatTime(localDt)}';
    debugPrint('_formatDateTime: Final formatted string: $formatted');
    return formatted;
  }
  
  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
  
  String _formatTime(DateTime dt) {
    // Ensure we're using local time
    // Note: dt should already be local when passed from _formatDateTime, but handle UTC just in case
    final localDt = dt.isUtc ? dt.toLocal() : dt;
    final hour24 = localDt.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = localDt.minute.toString().padLeft(2, '0');
    final ampm = hour24 < 12 ? 'AM' : 'PM';
    debugPrint('_formatTime: Input dt: $dt (isUtc: ${dt.isUtc}), localDt: $localDt (hour24: $hour24), formatted: $hour12:$minute $ampm');
    return '$hour12:$minute $ampm';
  }
  
  void _resetCreationState() {
    _pendingTitle = null;
    _pendingScheduledAt = null;
    _pendingDate = null;
    _pendingTime = null;
    _pendingEventTime = null;
    _pendingAdvanceReminderTime = null;
    _pendingAdvanceNoticeMinutes = null;
    _pendingRecurrence = ReminderRecurrence.none;
    _pendingNotes = null;
    _creationStepIndex = 0;
  }
  
  void _resetEditState() {
    _editingReminder = null;
    _pendingEditField = null;
    _pendingEditValue = null;
  }
}

