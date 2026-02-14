import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Service for managing notes in Supabase
class NotesService {
  static final _supabase = Supabase.instance.client;
  static const String _tableName = 'notes';

  /// Get all notes for the current user
  static Future<List<Note>> getNotes() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('NotesService: No user logged in');
        return [];
      }

      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final notes = (response as List)
          .map((json) => Note.fromJson(json as Map<String, dynamic>))
          .toList();

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
      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('id', noteId)
          .single();

      return Note.fromJson(response);
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
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('NotesService: No user logged in');
        return null;
      }

      final note = Note.create(
        userId: userId,
        title: title,
        content: content,
      );

      final response = await _supabase
          .from(_tableName)
          .insert(note.toInsertJson())
          .select()
          .single();

      final createdNote = Note.fromJson(response);
      debugPrint('NotesService: Created note ${createdNote.id}');
      return createdNote;
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
      final response = await _supabase
          .from(_tableName)
          .update({
            'title': title,
            'content': content,
          })
          .eq('id', noteId)
          .select()
          .single();

      final updatedNote = Note.fromJson(response);
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
      await _supabase
          .from(_tableName)
          .delete()
          .eq('id', noteId);

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
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .or('title.ilike.%$query%,content.ilike.%$query%')
          .order('updated_at', ascending: false);

      return (response as List)
          .map((json) => Note.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('NotesService: Error searching notes: $e');
      return [];
    }
  }
}

