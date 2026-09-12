import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// Service for managing notes in local storage
class NotesService {
  static const String _storageKey = 'notes';
  static final _uuid = const Uuid();

  /// Get all notes from local storage
  static Future<List<Note>> getNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data == null || data.isEmpty) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(data);
      final notes = decoded
          .map((json) => Note.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by updated_at descending
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      debugPrint('NotesService: Loaded ${notes.length} notes');
      return notes;
    } catch (e) {
      debugPrint('NotesService: Error loading notes: $e');
      return [];
    }
  }

  /// Get a single note by ID
  static Future<Note?> getNote(String noteId) async {
    try {
      final notes = await getNotes();
      return notes.firstWhere((n) => n.id == noteId);
    } catch (e) {
      debugPrint('NotesService: Error loading note $noteId: $e');
      return null;
    }
  }

  /// Create a new note
  static Future<Note?> createNote({
    required String title,
    String content = '',
  }) async {
    try {
      final now = DateTime.now();
      final note = Note(
        id: _uuid.v4(),
        userId: 'local_user',
        title: title,
        content: content,
        createdAt: now,
        updatedAt: now,
      );

      final notes = await getNotes();
      notes.insert(0, note); // Add at beginning (most recent)
      await _saveNotes(notes);

      debugPrint('NotesService: Created note ${note.id}');
      return note;
    } catch (e) {
      debugPrint('NotesService: Error creating note: $e');
      return null;
    }
  }

  /// Update an existing note
  static Future<Note?> updateNote({
    required String noteId,
    required String title,
    required String content,
  }) async {
    try {
      final notes = await getNotes();
      final index = notes.indexWhere((n) => n.id == noteId);
      if (index == -1) {
        debugPrint('NotesService: Note $noteId not found');
        return null;
      }

      final updatedNote = notes[index].copyWith(
        title: title,
        content: content,
        updatedAt: DateTime.now(),
      );

      notes[index] = updatedNote;
      await _saveNotes(notes);

      debugPrint('NotesService: Updated note ${updatedNote.id}');
      return updatedNote;
    } catch (e) {
      debugPrint('NotesService: Error updating note $noteId: $e');
      return null;
    }
  }

  /// Delete a note
  static Future<bool> deleteNote(String noteId) async {
    try {
      final notes = await getNotes();
      notes.removeWhere((n) => n.id == noteId);
      await _saveNotes(notes);

      debugPrint('NotesService: Deleted note $noteId');
      return true;
    } catch (e) {
      debugPrint('NotesService: Error deleting note $noteId: $e');
      return false;
    }
  }

  /// Search notes by title or content
  static Future<List<Note>> searchNotes(String query) async {
    try {
      final notes = await getNotes();
      final lowerQuery = query.toLowerCase();

      return notes.where((note) {
        return note.title.toLowerCase().contains(lowerQuery) ||
            note.content.toLowerCase().contains(lowerQuery);
      }).toList();
    } catch (e) {
      debugPrint('NotesService: Error searching notes: $e');
      return [];
    }
  }

  /// Save notes to local storage
  static Future<void> _saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final data = notes.map((n) => n.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(data));
  }
}
