import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../services/notes_service.dart';
import '../widgets/widgets.dart';
import '../widgets/confirm_dialog.dart';

/// Dark themed page for editing/creating a note
class NoteEditPage extends StatefulWidget {
  final Note? note; // null for creating new note
  final Function(Note) onNoteUpdated;
  final VoidCallback onNoteDeleted;

  const NoteEditPage({
    super.key,
    this.note,
    required this.onNoteUpdated,
    required this.onNoteDeleted,
  });

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  bool _isSaving = false;

  bool get isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      Note? savedNote;

      if (isEditing) {
        // Update existing note
        savedNote = await NotesService.updateNote(
          noteId: widget.note!.id,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
        );
      } else {
        // Create new note
        savedNote = await NotesService.createNote(
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
        );
      }

      setState(() => _isSaving = false);

      if (savedNote != null && mounted) {
        widget.onNoteUpdated(savedNote);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Note saved successfully' : 'Note created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save note'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving note: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDelete() async {
    if (!isEditing) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Note',
      message: 'This will permanently delete this note. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed && mounted) {
      setState(() => _isSaving = true);

      try {
        final success = await NotesService.deleteNote(widget.note!.id);
        
        setState(() => _isSaving = false);

        if (success && mounted) {
          widget.onNoteDeleted();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Note deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete note'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } catch (e) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting note: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar (matching AI Notepad style)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  // Back button (orange)
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
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
                    isEditing ? 'Edit Note' : 'Create New Note',
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
          AppSpacing.xl,
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
                // Title field
                AppTextField(
                  label: 'Title',
                  hint: 'Enter note title',
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  darkMode: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                
                // Content field
                AppTextField(
                  label: 'Content',
                  hint: 'Write your note here...',
                  controller: _contentController,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  darkMode: true,
                ),
                
                const SizedBox(height: AppSpacing.xl),
                
                // Save button (sky blue pill like alerts)
                AppButton(
                  label: 'Save Note',
                  onPressed: _isSaving ? null : _handleSave,
                  isLoading: _isSaving,
                  isFullWidth: true,
                  customColor: AppColors.dreamCloudBlue,
                ),
                
                // Delete button (only show when editing)
                if (isEditing) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Delete Note',
                    onPressed: _isSaving ? null : _handleDelete,
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
}
