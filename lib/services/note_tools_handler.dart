import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../providers/reminder_provider.dart';
import 'notes_service.dart';
import 'openai_service.dart';
import 'weather_service.dart';
import 'game_questions_service.dart';

/// Result of executing an AI tool
class AIToolResult {
  final bool success;
  final String message;
  final Note? note;
  final List<Note>? notes;
  final Reminder? alert;
  final List<Reminder>? alerts;
  
  AIToolResult({
    required this.success,
    required this.message,
    this.note,
    this.notes,
    this.alert,
    this.alerts,
  });
  
  /// Convert to JSON for tool response
  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    if (note != null) 'note_id': note!.id,
    if (note != null) 'note_title': note!.title,
    if (note != null) 'note_content': note!.content,
    if (note != null) 'instruction': 'Content provided for reference. Do not read aloud unless user asks.',
    if (notes != null) 'notes': notes!.map((n) => {
      'id': n.id,
      'title': n.title,
    }).toList(),
    if (alert != null) 'alert_id': alert!.id,
    if (alert != null) 'alert_title': alert!.title,
    if (alerts != null) 'alerts': alerts!.map((a) => {
      'id': a.id,
      'title': a.title,
      'scheduled_at': a.scheduledAt.toIso8601String(),
      'recurrence': a.recurrence.displayName,
    }).toList(),
  };
}

// Keep old name as alias for compatibility
typedef NoteToolResult = AIToolResult;

/// Navigation targets for AI
enum AINavigationTarget {
  notesList,
  noteView,
  chat,
  imageGenerator, // Chat page in image mode
  face,
  schedule, // Schedule/alerts page
  game, // Game display page
}

/// Unified handler for AI operations via function calling (notes + schedule + weather)
class NoteToolsHandler {
  // Reminder provider for schedule operations
  ReminderProvider? _reminderProvider;

  // Weather service for weather queries
  WeatherService? _weatherService;

  // Track the currently active/open note
  Note? _activeNote;

  Note? get activeNote => _activeNote;

  /// Set the reminder provider (injected from VoiceProvider)
  void setReminderProvider(ReminderProvider provider) {
    _reminderProvider = provider;
  }

  /// Set the weather service (injected with API key)
  void setWeatherService(WeatherService service) {
    _weatherService = service;
  }
  
  /// Callback when active note changes (for UI updates)
  Function(Note?)? onActiveNoteChanged;
  
  /// Callback for AI-triggered navigation
  /// Called when AI wants to show/navigate to something
  Function(AINavigationTarget, {Note? note})? onNavigate;
  
  /// Callback when notes list should be refreshed (create, update, delete)
  VoidCallback? onNotesListChanged;
  
  /// Flag to indicate we should pause after the current response plays
  bool _shouldPauseAfterResponse = false;

  /// Pending navigation to execute after response plays
  AINavigationTarget? _pendingNavigation;


  /// Check and clear the pause flag
  bool checkAndClearPauseFlag() {
    if (_shouldPauseAfterResponse) {
      _shouldPauseAfterResponse = false;
      return true;
    }
    return false;
  }

  /// Check and execute pending navigation
  void checkAndExecutePendingNavigation() {
    if (_pendingNavigation != null) {
      onNavigate?.call(_pendingNavigation!);
      _pendingNavigation = null;
    }
  }

  /// Callback when schedule list should be refreshed (create, update, delete)
  VoidCallback? onScheduleListChanged;

  /// Callback to start a game category
  Function(String category)? onStartGameCategory;

  /// Callback when a game question is fetched (to update display)
  Function(String question, String answer)? onGameQuestionFetched;

  /// Set the active note (for when UI updates it externally)
  /// Does NOT trigger onActiveNoteChanged to avoid infinite loops
  void setActiveNote(Note? note) {
    _activeNote = note;
    // Don't call onActiveNoteChanged here - this method is called FROM onActiveNoteChanged
    // callbacks, so calling it again would create an infinite loop
  }
  
  /// Define the tools available to the AI
  static List<Map<String, dynamic>> get toolDefinitions => [
    {
      'type': 'function',
      'function': {
        'name': 'create_note',
        'description': 'Create a new note with a title and content. Use this when the user asks you to save, note down, or remember something like a recipe, shopping list, or any information they want to keep. After creating, just confirm with the title - the user can see the content on screen.',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'The title of the note (e.g., "Chocolate Cake Recipe", "Shopping List")',
            },
            'content': {
              'type': 'string',
              'description': 'The full content of the note. Format nicely with line breaks and sections as appropriate.',
            },
          },
          'required': ['title', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'update_note',
        'description': 'Update a note with new content. Can update the currently active note, or find a note by title/ID first. Use this when the user wants to modify or change something in a note.',
        'parameters': {
          'type': 'object',
          'properties': {
            'search_title': {
              'type': 'string',
              'description': 'Search for a note by title to update (e.g., "shopping list", "recipe"). Use if no note is currently open.',
            },
            'note_id': {
              'type': 'string',
              'description': 'The ID of the note to update (from list_notes). Use if you have the note ID.',
            },
            'title': {
              'type': 'string',
              'description': 'New title for the note (optional, only if changing the title)',
            },
            'content': {
              'type': 'string',
              'description': 'The complete updated content of the note. Include all existing content plus changes.',
            },
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'append_to_note',
        'description': 'Add NEW content to the end of a note. Can append to the currently active note, or find a note by title/ID first. Only include items that are NOT already in the note.',
        'parameters': {
          'type': 'object',
          'properties': {
            'search_title': {
              'type': 'string',
              'description': 'Search for a note by title to append to (e.g., "shopping list", "todo list"). Use if no note is currently open.',
            },
            'note_id': {
              'type': 'string',
              'description': 'The ID of the note to append to (from list_notes). Use if you have the note ID.',
            },
            'content': {
              'type': 'string',
              'description': 'ONLY the new content to add (not already in the note)',
            },
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_active_note',
        'description': 'Get the content of the currently active/open note. Use this to reference the note content when the user asks about it.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_notes',
        'description': 'Get a list of all the user\'s saved notes. Use this when the user asks what notes they have or wants to find a specific note.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_note',
        'description': 'Show/display a note to the user by navigating to it. Use when user says "show me", "open", "display", or "pull up" a note. This will navigate to the note view screen.',
        'parameters': {
          'type': 'object',
          'properties': {
            'note_id': {
              'type': 'string',
              'description': 'The ID of the note to show (from list_notes)',
            },
            'search_title': {
              'type': 'string',
              'description': 'Search for a note by title (e.g., "cake recipe", "shopping list")',
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_notes_list',
        'description': 'Navigate to the notes list screen to show all notes. Use when user wants to see all their notes or browse them.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'go_back',
        'description': 'Navigate back to the main face/conversation screen. Use when user is done viewing a note and wants to return.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pause_conversation',
        'description': 'Pause the voice conversation and stop listening. Use when user says things like "pause", "stop", "hold on", "wait", "give me a moment", "be quiet", "stop listening", "take a break". The user can resume by tapping play or double-tapping the screen.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_chat',
        'description': 'Navigate to the chat/text input page. Use when user wants to type instead of speak. Examples: "switch to text", "I want to type", "open the chat", "let me type something".',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_image_generator',
        'description': 'Navigate to the image generator page. Use when user wants to create, generate, or make an image. Examples: "I want to make an image", "generate a picture", "create an image", "open the image generator".',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_schedule',
        'description': 'Navigate to the schedule page to display it on screen. Use when user wants to SEE or VIEW their schedule or alerts. Examples: "show my schedule", "open my alerts". Just navigate - don\'t read the list aloud.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'show_games',
        'description': 'Navigate to the games page menu. Use when user just wants to see games without starting one yet.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_game_question',
        'description': 'Get a question from the database to ask the user. Use when user wants to play riddles, jokes, or trivia. Call this to get a question, then ASK the question and WAIT for their answer. After they answer, tell them if correct and call this again for the next question.',
        'parameters': {
          'type': 'object',
          'properties': {
            'category': {
              'type': 'string',
              'enum': ['riddle', 'joke', 'trivia', 'random'],
              'description': 'Category: riddle, joke, trivia, or random for any',
            },
          },
          'required': ['category'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'close_note',
        'description': 'Close the currently active note. Use when the user is done working with it.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_note',
        'description': 'Delete a note permanently. Use with caution and only when explicitly requested.',
        'parameters': {
          'type': 'object',
          'properties': {
            'note_id': {
              'type': 'string',
              'description': 'The ID of the note to delete',
            },
          },
          'required': ['note_id'],
        },
      },
    },
    // ===== SCHEDULE/ALERT TOOLS =====
    {
      'type': 'function',
      'function': {
        'name': 'create_alert',
        'description': 'Create a new alert on the schedule. Use when user wants to set an alert, add something to their schedule, or be notified about something. Parse natural language like "tomorrow at 3pm", "in 2 hours", "every Monday at 9am".',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'What the alert is about (e.g., "Call mom", "Take medicine", "Meeting with John")',
            },
            'date': {
              'type': 'string',
              'description': 'The date for the alert in YYYY-MM-DD format (e.g., "2024-12-25")',
            },
            'time': {
              'type': 'string',
              'description': 'The time for the alert in HH:MM format, 24-hour (e.g., "14:30" for 2:30 PM)',
            },
            'recurrence': {
              'type': 'string',
              'enum': ['none', 'daily', 'weekly', 'monthly'],
              'description': 'How often to repeat: none (one-time), daily, weekly, or monthly',
            },
            'notes': {
              'type': 'string',
              'description': 'Optional additional notes or details for the alert',
            },
          },
          'required': ['title', 'date', 'time'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'update_alert',
        'description': 'Update an existing alert on the schedule. Use when user wants to change the time, title, or other details of an existing alert.',
        'parameters': {
          'type': 'object',
          'properties': {
            'alert_id': {
              'type': 'string',
              'description': 'The ID of the alert to update',
            },
            'title': {
              'type': 'string',
              'description': 'New title for the alert (optional)',
            },
            'date': {
              'type': 'string',
              'description': 'New date in YYYY-MM-DD format (optional)',
            },
            'time': {
              'type': 'string',
              'description': 'New time in HH:MM format, 24-hour (optional)',
            },
            'recurrence': {
              'type': 'string',
              'enum': ['none', 'daily', 'weekly', 'monthly'],
              'description': 'New recurrence setting (optional)',
            },
            'notes': {
              'type': 'string',
              'description': 'New notes for the alert (optional)',
            },
          },
          'required': ['alert_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_alert',
        'description': 'Delete an alert from the schedule permanently. Use when user wants to cancel or remove an alert.',
        'parameters': {
          'type': 'object',
          'properties': {
            'alert_id': {
              'type': 'string',
              'description': 'The ID of the alert to delete',
            },
          },
          'required': ['alert_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_alerts',
        'description': 'Get data about upcoming alerts (for AI reference). Use to check if a specific alert exists before updating/deleting. Prefer show_schedule for displaying to user.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    // ===== WEATHER TOOLS =====
    {
      'type': 'function',
      'function': {
        'name': 'get_weather',
        'description': 'Get current weather for a location. Use when the user asks about current weather, temperature, or conditions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'location': {
              'type': 'string',
              'description': 'City name, optionally with state/country (e.g., "London", "Paris, France", "Austin, TX")',
            },
          },
          'required': ['location'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_forecast',
        'description': 'Get weather forecast for a location. Use when user asks about future weather, tomorrow, this week, or a specific day.',
        'parameters': {
          'type': 'object',
          'properties': {
            'location': {
              'type': 'string',
              'description': 'City name, optionally with state/country',
            },
            'days_ahead': {
              'type': 'integer',
              'description': 'How many days ahead to forecast. 0=today, 1=tomorrow, 2-5 for later days. Default 1 (tomorrow).',
            },
          },
          'required': ['location'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_air_quality',
        'description': 'Get air quality and pollution levels for a location. Use when user asks about air quality, pollution, smog, or AQI.',
        'parameters': {
          'type': 'object',
          'properties': {
            'location': {
              'type': 'string',
              'description': 'City name, optionally with state/country',
            },
          },
          'required': ['location'],
        },
      },
    },
  ];
  
  /// Execute a tool call and return the result
  Future<NoteToolResult> executeTool(ToolCall toolCall) async {
    debugPrint('NoteToolsHandler: Executing tool ${toolCall.name}');
    
    switch (toolCall.name) {
      case 'create_note':
        return await _createNote(toolCall.arguments);
      case 'update_note':
        return await _updateNote(toolCall.arguments);
      case 'append_to_note':
        return await _appendToNote(toolCall.arguments);
      case 'get_active_note':
        return _getActiveNote();
      case 'list_notes':
        return await _listNotes();
      case 'show_note':
        return await _showNote(toolCall.arguments);
      case 'show_notes_list':
        return _showNotesList();
      case 'go_back':
        return _goBack();
      case 'pause_conversation':
        return _pauseConversation();
      case 'show_chat':
        return _showChat();
      case 'show_image_generator':
        return _showImageGenerator();
      case 'show_schedule':
        return _showSchedule();
      case 'show_games':
        return _showGames();
      case 'get_game_question':
        return await _getGameQuestion(toolCall.arguments);
      case 'close_note':
        return _closeNote();
      case 'delete_note':
        return await _deleteNote(toolCall.arguments);
      // Alert/Schedule tools
      case 'create_alert':
        return await _createAlert(toolCall.arguments);
      case 'update_alert':
        return await _updateAlert(toolCall.arguments);
      case 'delete_alert':
        return await _deleteAlert(toolCall.arguments);
      case 'list_alerts':
        return await _listAlerts();
      // Weather tools
      case 'get_weather':
        return await _getWeather(toolCall.arguments);
      case 'get_forecast':
        return await _getForecast(toolCall.arguments);
      case 'get_air_quality':
        return await _getAirQuality(toolCall.arguments);
      default:
        return AIToolResult(
          success: false,
          message: 'Unknown tool: ${toolCall.name}',
        );
    }
  }
  
  Future<NoteToolResult> _createNote(Map<String, dynamic> args) async {
    final title = args['title'] as String? ?? 'Untitled Note';
    final content = args['content'] as String? ?? '';
    
    try {
      final note = await NotesService.createNote(
        title: title,
        content: content,
      );
      
      if (note != null) {
        // Make the new note active
        _activeNote = note;
        onActiveNoteChanged?.call(note);
        onNotesListChanged?.call(); // Refresh notes list
        
        return NoteToolResult(
          success: true,
          message: 'Created "$title" note. Is there anything else I can help you with?',
          note: note,
        );
      } else {
        return NoteToolResult(
          success: false,
          message: 'Failed to create note. Please try again.',
        );
      }
    } catch (e) {
      debugPrint('Error creating note: $e');
      return NoteToolResult(
        success: false,
        message: 'Error creating note: $e',
      );
    }
  }
  
  Future<NoteToolResult> _updateNote(Map<String, dynamic> args) async {
    debugPrint('NoteToolsHandler: _updateNote called, activeNote: ${_activeNote?.title ?? "null"}');
    
    final searchTitle = args['search_title'] as String?;
    final noteId = args['note_id'] as String?;
    
    // If no active note, try to find one by ID or title
    if (_activeNote == null) {
      if (noteId != null && noteId.isNotEmpty) {
        debugPrint('NoteToolsHandler: No active note, searching by ID: $noteId');
        final note = await NotesService.getNote(noteId);
        if (note != null) {
          _activeNote = note;
          // Don't call onActiveNoteChanged here - wait until after the update
        }
      } else if (searchTitle != null && searchTitle.isNotEmpty) {
        debugPrint('NoteToolsHandler: No active note, searching by title: $searchTitle');
        final notes = await NotesService.searchNotes(searchTitle);
        if (notes.isNotEmpty) {
          _activeNote = notes.first;
          // Don't call onActiveNoteChanged here - wait until after the update
          debugPrint('NoteToolsHandler: Found note by title: ${_activeNote!.title}');
        }
      }
    }
    
    if (_activeNote == null) {
      debugPrint('NoteToolsHandler: ERROR - No active note for update');
      return NoteToolResult(
        success: false,
        message: 'No note is currently open. Please open or create a note first.',
      );
    }
    
    final newTitle = args['title'] as String? ?? _activeNote!.title;
    final newContent = args['content'] as String?;
    
    if (newContent == null) {
      debugPrint('NoteToolsHandler: ERROR - No content provided for update');
      return NoteToolResult(
        success: false,
        message: 'No content provided for update.',
      );
    }
    
    debugPrint('NoteToolsHandler: Updating note "${_activeNote!.title}" with new content length: ${newContent.length}');
    
    try {
      final updated = await NotesService.updateNote(
        noteId: _activeNote!.id,
        title: newTitle,
        content: newContent,
      );
      
      if (updated != null) {
        _activeNote = updated;
        onActiveNoteChanged?.call(updated);
        onNotesListChanged?.call(); // Refresh notes list
        
        return NoteToolResult(
          success: true,
          message: 'Updated the note.',
          note: updated,
        );
      } else {
        return NoteToolResult(
          success: false,
          message: 'Failed to update note.',
        );
      }
    } catch (e) {
      debugPrint('Error updating note: $e');
      return NoteToolResult(
        success: false,
        message: 'Error updating note: $e',
      );
    }
  }
  
  Future<NoteToolResult> _appendToNote(Map<String, dynamic> args) async {
    debugPrint('NoteToolsHandler: _appendToNote called, activeNote: ${_activeNote?.title ?? "null"}');
    
    final searchTitle = args['search_title'] as String?;
    final noteId = args['note_id'] as String?;
    
    // If no active note, try to find one by ID or title
    if (_activeNote == null) {
      if (noteId != null && noteId.isNotEmpty) {
        debugPrint('NoteToolsHandler: No active note, searching by ID: $noteId');
        final note = await NotesService.getNote(noteId);
        if (note != null) {
          _activeNote = note;
          // Don't call onActiveNoteChanged here - wait until after the append
        }
      } else if (searchTitle != null && searchTitle.isNotEmpty) {
        debugPrint('NoteToolsHandler: No active note, searching by title: $searchTitle');
        final notes = await NotesService.searchNotes(searchTitle);
        if (notes.isNotEmpty) {
          _activeNote = notes.first;
          // Don't call onActiveNoteChanged here - wait until after the append
          debugPrint('NoteToolsHandler: Found note by title: ${_activeNote!.title}');
        }
      }
    }
    
    if (_activeNote == null) {
      debugPrint('NoteToolsHandler: ERROR - No active note for append');
      return NoteToolResult(
        success: false,
        message: 'No note is currently open. Please open or create a note first.',
      );
    }
    
    final contentToAppend = args['content'] as String?;
    
    if (contentToAppend == null || contentToAppend.isEmpty) {
      debugPrint('NoteToolsHandler: ERROR - No content to append');
      return NoteToolResult(
        success: false,
        message: 'No content provided to append.',
      );
    }
    
    debugPrint('NoteToolsHandler: Appending to note "${_activeNote!.title}": $contentToAppend');
    final newContent = _activeNote!.content.isEmpty 
        ? contentToAppend 
        : '${_activeNote!.content}\n\n$contentToAppend';
    
    try {
      final updated = await NotesService.updateNote(
        noteId: _activeNote!.id,
        title: _activeNote!.title,
        content: newContent,
      );
      
      if (updated != null) {
        _activeNote = updated;
        onActiveNoteChanged?.call(updated);
        onNotesListChanged?.call(); // Refresh notes list
        
        return NoteToolResult(
          success: true,
          message: 'Added to the note.',
          note: updated,
        );
      } else {
        return NoteToolResult(
          success: false,
          message: 'Failed to append to note.',
        );
      }
    } catch (e) {
      debugPrint('Error appending to note: $e');
      return NoteToolResult(
        success: false,
        message: 'Error appending to note: $e',
      );
    }
  }
  
  NoteToolResult _getActiveNote() {
    if (_activeNote == null) {
      return NoteToolResult(
        success: false,
        message: 'No note is currently open.',
      );
    }
    
    return NoteToolResult(
      success: true,
      message: 'Current note: ${_activeNote!.title}',
      note: _activeNote,
    );
  }
  
  Future<NoteToolResult> _listNotes() async {
    try {
      debugPrint('NoteToolsHandler: Calling NotesService.getNotes()...');
      final notes = await NotesService.getNotes();
      debugPrint('NoteToolsHandler: Got ${notes.length} notes');
      
      if (notes.isEmpty) {
        return NoteToolResult(
          success: true,
          message: 'You don\'t have any notes yet.',
          notes: [],
        );
      }
      
      // List the note titles for debugging
      for (final note in notes) {
        debugPrint('NoteToolsHandler: Note - "${note.title}"');
      }
      
      return NoteToolResult(
        success: true,
        message: 'Found ${notes.length} note(s): ${notes.map((n) => n.title).join(", ")}.',
        notes: notes,
      );
    } catch (e) {
      debugPrint('Error listing notes: $e');
      return NoteToolResult(
        success: false,
        message: 'Error listing notes: $e',
      );
    }
  }
  
  /// Show a note - navigates to the note view page
  Future<NoteToolResult> _showNote(Map<String, dynamic> args) async {
    final noteId = args['note_id'] as String?;
    final searchTitle = args['search_title'] as String?;
    
    debugPrint('NoteToolsHandler: _showNote called with noteId: $noteId, searchTitle: $searchTitle');
    
    try {
      Note? note;
      
      if (noteId != null && noteId.isNotEmpty) {
        // Find by ID
        debugPrint('NoteToolsHandler: Searching by ID: $noteId');
        note = await NotesService.getNote(noteId);
        debugPrint('NoteToolsHandler: Found by ID: ${note?.title ?? "null"}');
      } else if (searchTitle != null && searchTitle.isNotEmpty) {
        // Search by title
        debugPrint('NoteToolsHandler: Searching by title: $searchTitle');
        final notes = await NotesService.searchNotes(searchTitle);
        debugPrint('NoteToolsHandler: Search returned ${notes.length} results');
        if (notes.isNotEmpty) {
          note = notes.first; // Take the best match
          debugPrint('NoteToolsHandler: Using first result: ${note.title}');
        }
      } else {
        return NoteToolResult(
          success: false,
          message: 'Please specify which note to show.',
        );
      }
      
      if (note != null) {
        _activeNote = note;
        onActiveNoteChanged?.call(note);
        
        // Trigger navigation to the note view
        onNavigate?.call(AINavigationTarget.noteView, note: note);
        
        return NoteToolResult(
          success: true,
          message: 'Here is your "${note.title}" note. Is there anything else I can help you with?',
          note: note,
        );
      } else {
        return NoteToolResult(
          success: false,
          message: 'I couldn\'t find a note with that name. Would you like me to list your notes?',
        );
      }
    } catch (e) {
      debugPrint('Error showing note: $e');
      return NoteToolResult(
        success: false,
        message: 'Error finding note: $e',
      );
    }
  }
  
  /// Show the notes list page
  NoteToolResult _showNotesList() {
    onNavigate?.call(AINavigationTarget.notesList);
    
    return NoteToolResult(
      success: true,
      message: 'Here you go.',
    );
  }
  
  /// Navigate back to the face/conversation page
  NoteToolResult _goBack() {
    _activeNote = null;
    onActiveNoteChanged?.call(null);
    onNavigate?.call(AINavigationTarget.face);
    
    return NoteToolResult(
      success: true,
      message: 'Sure. What else can I help you with?',
    );
  }
  
  /// Pause the voice conversation (sets flag, actual pause happens after response plays)
  NoteToolResult _pauseConversation() {
    _shouldPauseAfterResponse = true;
    debugPrint('Pause requested - will pause after response plays');
    
    return NoteToolResult(
      success: true,
      message: 'Okay, I\'ll be here when you\'re ready. Just tap play to continue.',
    );
  }
  
  /// Navigate to the chat/text page
  NoteToolResult _showChat() {
    onNavigate?.call(AINavigationTarget.chat);
    
    return NoteToolResult(
      success: true,
      message: 'Here is the chat. You can type your message.',
    );
  }
  
  /// Navigate to the image generator page
  NoteToolResult _showImageGenerator() {
    onNavigate?.call(AINavigationTarget.imageGenerator);
    
    return NoteToolResult(
      success: true,
      message: 'Here is the image generator. Type a description of what you want to create.',
    );
  }
  
  /// Navigate to the schedule page
  NoteToolResult _showSchedule() {
    onNavigate?.call(AINavigationTarget.schedule);

    return NoteToolResult(
      success: true,
      message: 'Here you go.',
    );
  }

  /// Navigate to the games page
  NoteToolResult _showGames() {
    // Just navigate to game page - user taps a category button to start
    onNavigate?.call(AINavigationTarget.game);

    return NoteToolResult(
      success: true,
      message: 'Here are the games. Tap a category to start!',
    );
  }

  /// Get a game question from the database for AI to ask
  Future<NoteToolResult> _getGameQuestion(Map<String, dynamic> args) async {
    final category = args['category'] as String? ?? 'random';

    try {
      // Navigate to game page to show the question
      onNavigate?.call(AINavigationTarget.game);

      // Fetch question from database
      final question = await GameQuestionsService.getNextQuestion(category);

      if (question == null) {
        return NoteToolResult(
          success: false,
          message: 'No more questions available in this category. Try another category!',
        );
      }

      // Mark as used so we don't repeat
      await GameQuestionsService.markAsUsed(question.id);

      // Update game display with the question
      onGameQuestionFetched?.call(question.question, question.answer);

      // Return question AND answer to AI - AI will ask and evaluate
      return NoteToolResult(
        success: true,
        message: '''
QUESTION TO ASK: ${question.question}

CORRECT ANSWER: ${question.answer}

INSTRUCTIONS:
1. Ask the user this question naturally (read it aloud)
2. Wait for their answer
3. If they get it right (close enough match), congratulate them!
4. If wrong, tell them the correct answer
5. Then call get_game_question again for the next question
6. Keep going until they want to stop

DO NOT reveal the answer before they try!
''',
      );
    } catch (e) {
      debugPrint('Error getting game question: $e');
      return NoteToolResult(
        success: false,
        message: 'Error getting question: $e',
      );
    }
  }

  NoteToolResult _closeNote() {
    if (_activeNote == null) {
      return NoteToolResult(
        success: true,
        message: 'No note was open.',
      );
    }
    
    final closedTitle = _activeNote!.title;
    _activeNote = null;
    onActiveNoteChanged?.call(null);
    
    return NoteToolResult(
      success: true,
      message: 'Closed the note "$closedTitle".',
    );
  }
  
  Future<NoteToolResult> _deleteNote(Map<String, dynamic> args) async {
    final noteId = args['note_id'] as String?;
    
    if (noteId == null || noteId.isEmpty) {
      return NoteToolResult(
        success: false,
        message: 'Please specify which note to delete.',
      );
    }
    
    try {
      // Get note info before deleting for the message
      final note = await NotesService.getNote(noteId);
      final noteTitle = note?.title ?? 'the note';
      
      final success = await NotesService.deleteNote(noteId);
      
      if (success) {
        // If the deleted note was active, clear it
        if (_activeNote?.id == noteId) {
          _activeNote = null;
          onActiveNoteChanged?.call(null);
        }
        onNotesListChanged?.call(); // Refresh notes list
        
        return NoteToolResult(
          success: true,
          message: 'Deleted "$noteTitle".',
        );
      } else {
        return NoteToolResult(
          success: false,
          message: 'Failed to delete note.',
        );
      }
    } catch (e) {
      debugPrint('Error deleting note: $e');
      return NoteToolResult(
        success: false,
        message: 'Error deleting note: $e',
      );
    }
  }
  
  // ===== ALERT/SCHEDULE METHODS =====
  
  /// Create a new alert/reminder
  Future<AIToolResult> _createAlert(Map<String, dynamic> args) async {
    if (_reminderProvider == null) {
      return AIToolResult(
        success: false,
        message: 'Schedule system not available.',
      );
    }
    
    final title = args['title'] as String?;
    final dateStr = args['date'] as String?;
    final timeStr = args['time'] as String?;
    final recurrenceStr = args['recurrence'] as String? ?? 'none';
    final notes = args['notes'] as String?;
    
    if (title == null || title.isEmpty) {
      return AIToolResult(
        success: false,
        message: 'Please provide a title for the alert.',
      );
    }
    
    if (dateStr == null || timeStr == null) {
      return AIToolResult(
        success: false,
        message: 'Please provide both date and time for the alert.',
      );
    }
    
    try {
      // Parse date and time with better error handling
      DateTime scheduledAt;
      
      try {
        // Try parsing as ISO 8601 first (e.g., "2024-12-25T14:30:00")
        if (dateStr.contains('T')) {
          scheduledAt = DateTime.parse(dateStr);
        } else {
          // Parse separate date and time
          final dateParts = dateStr.split('-');
          final timeParts = timeStr.split(':');
          
          if (dateParts.length != 3) {
            return AIToolResult(
              success: false,
              message: 'Invalid date format "$dateStr". Please use YYYY-MM-DD format (e.g., "2024-12-25").',
            );
          }
          
          if (timeParts.length < 2) {
            return AIToolResult(
              success: false,
              message: 'Invalid time format "$timeStr". Please use HH:MM format in 24-hour time (e.g., "14:30" for 2:30 PM).',
            );
          }
          
          final year = int.tryParse(dateParts[0]);
          final month = int.tryParse(dateParts[1]);
          final day = int.tryParse(dateParts[2]);
          final hour = int.tryParse(timeParts[0]);
          final minute = int.tryParse(timeParts[1]);
          
          if (year == null || month == null || day == null || hour == null || minute == null) {
            return AIToolResult(
              success: false,
              message: 'Could not parse date "$dateStr" or time "$timeStr". Please use numeric values.',
            );
          }
          
          scheduledAt = DateTime(year, month, day, hour, minute);
        }
      } catch (e) {
        return AIToolResult(
          success: false,
          message: 'Could not parse date/time: $e. Use YYYY-MM-DD for date and HH:MM for time.',
        );
      }
      
      // Parse recurrence
      ReminderRecurrence recurrence;
      switch (recurrenceStr.toLowerCase()) {
        case 'daily':
          recurrence = ReminderRecurrence.daily;
          break;
        case 'weekly':
          recurrence = ReminderRecurrence.weekly;
          break;
        case 'monthly':
          recurrence = ReminderRecurrence.monthly;
          break;
        default:
          recurrence = ReminderRecurrence.none;
      }
      
      debugPrint('Creating alert: $title at $scheduledAt, recurrence: $recurrence');
      
      final reminder = await _reminderProvider!.createReminder(
        title: title,
        scheduledAt: scheduledAt,
        recurrence: recurrence,
        notes: notes,
      );
      
      if (reminder != null) {
        onScheduleListChanged?.call(); // Refresh schedule list
        
        // Format confirmation message
        final timeFormatted = _formatTime(scheduledAt);
        final dateFormatted = _formatDate(scheduledAt);
        String confirmMsg = 'Done! I\'ve added "$title" to your schedule for $dateFormatted at $timeFormatted.';
        if (recurrence != ReminderRecurrence.none) {
          confirmMsg += ' It will repeat ${recurrence.displayName.toLowerCase()}.';
        }
        
        return AIToolResult(
          success: true,
          message: confirmMsg,
          alert: reminder,
        );
      } else {
        return AIToolResult(
          success: false,
          message: 'Failed to create the alert. Please try again.',
        );
      }
    } catch (e) {
      debugPrint('Error creating alert: $e');
      return AIToolResult(
        success: false,
        message: 'Error creating alert: $e',
      );
    }
  }
  
  /// Update an existing alert
  Future<AIToolResult> _updateAlert(Map<String, dynamic> args) async {
    if (_reminderProvider == null) {
      return AIToolResult(
        success: false,
        message: 'Schedule system not available.',
      );
    }
    
    final alertId = args['alert_id'] as String?;
    
    if (alertId == null || alertId.isEmpty) {
      return AIToolResult(
        success: false,
        message: 'Please specify which alert to update.',
      );
    }
    
    try {
      final existing = _reminderProvider!.getReminderById(alertId);
      if (existing == null) {
        return AIToolResult(
          success: false,
          message: 'Could not find that alert.',
        );
      }
      
      // Parse optional updates
      final title = args['title'] as String?;
      final dateStr = args['date'] as String?;
      final timeStr = args['time'] as String?;
      final recurrenceStr = args['recurrence'] as String?;
      final notes = args['notes'] as String?;
      
      DateTime? scheduledAt;
      if (dateStr != null && timeStr != null) {
        final dateParts = dateStr.split('-');
        final timeParts = timeStr.split(':');
        scheduledAt = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
      } else if (dateStr != null) {
        // Just date, keep existing time
        final dateParts = dateStr.split('-');
        scheduledAt = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          existing.scheduledAt.hour,
          existing.scheduledAt.minute,
        );
      } else if (timeStr != null) {
        // Just time, keep existing date
        final timeParts = timeStr.split(':');
        scheduledAt = DateTime(
          existing.scheduledAt.year,
          existing.scheduledAt.month,
          existing.scheduledAt.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
      }
      
      ReminderRecurrence? recurrence;
      if (recurrenceStr != null) {
        switch (recurrenceStr.toLowerCase()) {
          case 'daily':
            recurrence = ReminderRecurrence.daily;
            break;
          case 'weekly':
            recurrence = ReminderRecurrence.weekly;
            break;
          case 'monthly':
            recurrence = ReminderRecurrence.monthly;
            break;
          case 'none':
            recurrence = ReminderRecurrence.none;
            break;
        }
      }
      
      final success = await _reminderProvider!.updateReminder(
        reminderId: alertId,
        title: title,
        scheduledAt: scheduledAt,
        recurrence: recurrence,
        notes: notes,
      );
      
      if (success) {
        onScheduleListChanged?.call();
        return AIToolResult(
          success: true,
          message: 'Updated the alert.',
        );
      } else {
        return AIToolResult(
          success: false,
          message: 'Failed to update the alert.',
        );
      }
    } catch (e) {
      debugPrint('Error updating alert: $e');
      return AIToolResult(
        success: false,
        message: 'Error updating alert: $e',
      );
    }
  }
  
  /// Delete an alert
  Future<AIToolResult> _deleteAlert(Map<String, dynamic> args) async {
    if (_reminderProvider == null) {
      return AIToolResult(
        success: false,
        message: 'Schedule system not available.',
      );
    }
    
    final alertId = args['alert_id'] as String?;
    
    if (alertId == null || alertId.isEmpty) {
      return AIToolResult(
        success: false,
        message: 'Please specify which alert to delete.',
      );
    }
    
    try {
      final existing = _reminderProvider!.getReminderById(alertId);
      final alertTitle = existing?.title ?? 'the alert';
      
      final success = await _reminderProvider!.deleteReminder(alertId);
      
      if (success) {
        onScheduleListChanged?.call();
        return AIToolResult(
          success: true,
          message: 'Deleted "$alertTitle".',
        );
      } else {
        return AIToolResult(
          success: false,
          message: 'Failed to delete the alert.',
        );
      }
    } catch (e) {
      debugPrint('Error deleting alert: $e');
      return AIToolResult(
        success: false,
        message: 'Error deleting alert: $e',
      );
    }
  }
  
  /// List all alerts
  Future<AIToolResult> _listAlerts() async {
    if (_reminderProvider == null) {
      return AIToolResult(
        success: false,
        message: 'Schedule system not available.',
      );
    }
    
    try {
      final alerts = _reminderProvider!.activeReminders;
      
      if (alerts.isEmpty) {
        return AIToolResult(
          success: true,
          message: 'You don\'t have any upcoming alerts.',
          alerts: [],
        );
      }
      
      // Just return count - don't read the full list aloud
      // The alerts data is included for reference if user asks specifics
      return AIToolResult(
        success: true,
        message: 'You have ${alerts.length} upcoming alert${alerts.length == 1 ? '' : 's'}.',
        alerts: alerts,
      );
    } catch (e) {
      debugPrint('Error listing alerts: $e');
      return AIToolResult(
        success: false,
        message: 'Error listing alerts: $e',
      );
    }
  }

  /// Get weather for a location
  Future<AIToolResult> _getWeather(Map<String, dynamic> args) async {
    if (_weatherService == null) {
      return AIToolResult(
        success: false,
        message: 'Weather service not configured. Please set up an OpenWeather API key.',
      );
    }

    final location = args['location'] as String?;
    if (location == null || location.isEmpty) {
      return AIToolResult(
        success: false,
        message: 'Please specify a location to check the weather.',
      );
    }

    try {
      final result = await _weatherService!.getWeather(location);

      if (result.success) {
        return AIToolResult(
          success: true,
          message: result.toSummary(),
        );
      } else {
        return AIToolResult(
          success: false,
          message: result.error ?? 'Unable to get weather for $location',
        );
      }
    } catch (e) {
      debugPrint('Error getting weather: $e');
      return AIToolResult(
        success: false,
        message: 'Error getting weather: $e',
      );
    }
  }

  /// Get weather forecast for a location
  Future<AIToolResult> _getForecast(Map<String, dynamic> args) async {
    if (_weatherService == null) {
      return AIToolResult(
        success: false,
        message: 'Weather service not configured. Please set up an OpenWeather API key.',
      );
    }

    final location = args['location'] as String?;
    if (location == null || location.isEmpty) {
      return AIToolResult(
        success: false,
        message: 'Please specify a location to check the forecast.',
      );
    }

    final daysAhead = args['days_ahead'] as int? ?? 1;

    try {
      final result = await _weatherService!.getForecast(location);

      if (result.success && result.forecasts != null) {
        final summary = _buildForecastSummary(result, daysAhead);
        return AIToolResult(
          success: true,
          message: summary,
        );
      } else {
        return AIToolResult(
          success: false,
          message: result.error ?? 'Unable to get forecast for $location',
        );
      }
    } catch (e) {
      debugPrint('Error getting forecast: $e');
      return AIToolResult(
        success: false,
        message: 'Error getting forecast: $e',
      );
    }
  }

  /// Build forecast summary for a specific day
  String _buildForecastSummary(ForecastResult result, int daysAhead) {
    if (result.forecasts == null || result.forecasts!.isEmpty) {
      return 'No forecast data available';
    }

    final now = DateTime.now();
    final targetDate = DateTime(now.year, now.month, now.day + daysAhead);

    // Find forecasts for the target day
    final dayForecasts = result.forecasts!.where((f) {
      final date = DateTime(f.dateTime.year, f.dateTime.month, f.dateTime.day);
      return date.year == targetDate.year &&
             date.month == targetDate.month &&
             date.day == targetDate.day;
    }).toList();

    if (dayForecasts.isEmpty) {
      return 'No forecast available for that day';
    }

    String dayName;
    if (daysAhead == 0) {
      dayName = 'Today';
    } else if (daysAhead == 1) {
      dayName = 'Tomorrow';
    } else {
      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      dayName = weekdays[targetDate.weekday - 1];
    }

    // Get morning, afternoon, evening forecasts
    ForecastEntry? morning, afternoon, evening;
    for (final f in dayForecasts) {
      final hour = f.dateTime.hour;
      if (hour >= 6 && hour < 12) morning = f;
      if (hour >= 12 && hour < 18) afternoon = f;
      if (hour >= 18 && hour < 22) evening = f;
    }

    final buffer = StringBuffer('$dayName in ${result.location}: ');
    if (morning != null) buffer.write('Morning ${morning.temperature.round()} degrees ${morning.description}. ');
    if (afternoon != null) buffer.write('Afternoon ${afternoon.temperature.round()} degrees ${afternoon.description}. ');
    if (evening != null) buffer.write('Evening ${evening.temperature.round()} degrees ${evening.description}.');

    // If no specific times found, just use first entry
    if (morning == null && afternoon == null && evening == null && dayForecasts.isNotEmpty) {
      final f = dayForecasts.first;
      buffer.write('${f.temperature.round()} degrees, ${f.description}.');
    }

    return buffer.toString();
  }

  /// Get air quality for a location
  Future<AIToolResult> _getAirQuality(Map<String, dynamic> args) async {
    if (_weatherService == null) {
      return AIToolResult(
        success: false,
        message: 'Weather service not configured. Please set up an OpenWeather API key.',
      );
    }

    final location = args['location'] as String?;
    if (location == null || location.isEmpty) {
      return AIToolResult(
        success: false,
        message: 'Please specify a location to check air quality.',
      );
    }

    try {
      final result = await _weatherService!.getAirQuality(location);

      if (result.success) {
        return AIToolResult(
          success: true,
          message: result.toSummary(),
        );
      } else {
        return AIToolResult(
          success: false,
          message: result.error ?? 'Unable to get air quality for $location',
        );
      }
    } catch (e) {
      debugPrint('Error getting air quality: $e');
      return AIToolResult(
        success: false,
        message: 'Error getting air quality: $e',
      );
    }
  }

  /// Helper to format time for display
  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }
  
  /// Helper to format date for display
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final targetDate = DateTime(dt.year, dt.month, dt.day);
    
    if (targetDate == today) {
      return 'today';
    } else if (targetDate == tomorrow) {
      return 'tomorrow';
    } else {
      final months = ['January', 'February', 'March', 'April', 'May', 'June',
                     'July', 'August', 'September', 'October', 'November', 'December'];
      return '${months[dt.month - 1]} ${dt.day}';
    }
  }
  
  /// Get context about the active note to include in the system prompt
  String getActiveNoteContext() {
    // Include current date/time so AI can calculate "tomorrow", "next week", etc.
    final now = DateTime.now();
    final currentDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final currentWeekday = weekdays[now.weekday - 1];
    
    final instructions = '''

CURRENT DATE/TIME: $currentWeekday, $currentDate at $currentTime
Use this to calculate dates like "tomorrow", "next Monday", "in 2 hours", etc.

NAVIGATION, NOTES & SCHEDULE CAPABILITIES:
You can navigate the app, manage notes, and handle the schedule with alerts naturally.

NOTES - When users say things like:
- "show me the shopping list" → use show_note to display it
- "make a note about this" → use create_note
- "add eggs to the shopping list" → use append_to_note with search_title="shopping list"
- "update my recipe" → use update_note with search_title="recipe"
- "show me my notes" → use show_notes_list

IMPORTANT: When updating or appending to a note by name, use the search_title parameter to find it first. Don't say you can't update if no note is open - use search_title to find and update it.

SCHEDULE/ALERTS - When users say things like:
- "remind me to call mom tomorrow at 3pm" → calculate tomorrow's date and use create_alert
- "set an alert for 7am every day" → use create_alert with recurrence="daily"
- "what's on my schedule" → use list_alerts or show_schedule
- "delete the meeting alert" → FIRST use list_alerts to find the alert ID, THEN use delete_alert
- "change my alert to 4pm" → FIRST use list_alerts to find the alert ID, THEN use update_alert
- "show my schedule" → use show_schedule (just navigates, don't read the list)

ALERT WORKFLOW:
1. To CREATE: Calculate the exact date (YYYY-MM-DD) and time (HH:MM in 24-hour format) from user's request
2. To UPDATE/DELETE by name: First call list_alerts to get the alert_id, then call update_alert or delete_alert
3. If user says "remind me" - treat it as creating an alert, use "schedule" terminology in response

TERMINOLOGY: Always say "alert" or "schedule" instead of "reminder". Say "I've added it to your schedule" not "I've set a reminder".

NAVIGATION:
- "go back" or "close the note" → use go_back to return to conversation
- "switch to text" or "I want to type" → use show_chat
- "make an image" or "generate a picture" → use show_image_generator
- "let's play a game", "games", "riddles", "jokes", "trivia" → use show_games

GAMES - IMPORTANT:
- When user wants riddles/jokes/trivia, call get_game_question with the category
- The tool returns a QUESTION and ANSWER from the database
- ASK the question to the user and WAIT for their answer
- Evaluate their answer - if close enough, congratulate them; if wrong, reveal the answer
- Then call get_game_question again for the next question
- Keep the game going until they want to stop
- DO NOT make up your own questions - always use get_game_question to fetch from database

PAUSE:
- "pause", "stop", "hold on", "wait", "be quiet", "stop listening" → use pause_conversation
- After pausing, the user can resume by tapping play or double-tapping the screen

IMPORTANT: Don't read note content aloud unless asked. After creating notes or alerts, just confirm briefly.
''';

    if (_activeNote == null) {
      return instructions;
    }

    // Include full content so AI can reference it when asked
    return '''$instructions
CURRENTLY ACTIVE NOTE:
Title: "${_activeNote!.title}"
Content:
${_activeNote!.content}

(The user is viewing this note on screen. You can reference, update, or append to it. Only read the content aloud if asked.)
''';
  }
}

