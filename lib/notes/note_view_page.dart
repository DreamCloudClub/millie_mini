import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/voice_provider.dart';
import '../utils/constants.dart';
import '../face/control_bar.dart';
import 'note_edit_page.dart';

/// Dark themed page for viewing a note (read-only)
class NoteViewPage extends StatefulWidget {
  final Note note;
  final Function(Note) onNoteUpdated;
  final VoidCallback onNoteDeleted;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onExit;

  const NoteViewPage({
    super.key,
    required this.note,
    required this.onNoteUpdated,
    required this.onNoteDeleted,
    required this.onPause,
    required this.onPlay,
    required this.onRefresh,
    required this.onExit,
  });

  @override
  State<NoteViewPage> createState() => _NoteViewPageState();
}

class _NoteViewPageState extends State<NoteViewPage> {
  late Note _currentNote;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    
    // Listen for AI-triggered note updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupNoteUpdateListener();
    });
  }
  
  void _setupNoteUpdateListener() {
    final voiceProvider = context.read<VoiceProvider>();
    voiceProvider.noteToolsHandler.onActiveNoteChanged = (note) {
      // If the updated note is the one we're viewing, refresh the UI
      if (note != null && note.id == _currentNote.id) {
        setState(() {
          _currentNote = note;
        });
        widget.onNoteUpdated(note);
      }
    };
  }

  void _openEditPage() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => NoteEditPage(
          note: _currentNote,
          onNoteUpdated: (updatedNote) {
            setState(() {
              _currentNote = updatedNote;
            });
            widget.onNoteUpdated(updatedNote);
          },
          onNoteDeleted: () {
            widget.onNoteDeleted();
            Navigator.pop(context); // Close view page after delete
          },
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
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
                  // Title (centered)
                  const Expanded(
                    child: Text(
                      'AI Notepad',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Edit button (rounded square with gear icon)
                  GestureDetector(
                    onTap: _openEditPage,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Note content in blue border container
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blue,
                      width: 1,
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title (centered)
                        Center(
                          child: Text(
                            _currentNote.title.isEmpty 
                                ? 'Untitled Note' 
                                : _currentNote.title,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        const SizedBox(height: AppSpacing.sm),
                        
                        // Date (centered)
                        Center(
                          child: Text(
                            _formatDate(_currentNote.updatedAt),
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: AppSpacing.md),
                        
                        // Divider line
                        Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        
                        const SizedBox(height: AppSpacing.md),
                        
                        // Content (left-aligned)
                        Text(
                          _currentNote.content.isEmpty 
                              ? 'No content' 
                              : _currentNote.content,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 16,
                            color: _currentNote.content.isEmpty 
                                ? Colors.white.withOpacity(0.3) 
                                : Colors.white.withOpacity(0.9),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: AppSpacing.sm),
            
            // Status text
            Consumer<VoiceProvider>(
              builder: (context, voiceProvider, _) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
            
            // Bottom control bar
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today at ${_formatTime(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${_formatTime(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${date.minute.toString().padLeft(2, '0')} $period';
  }
}
