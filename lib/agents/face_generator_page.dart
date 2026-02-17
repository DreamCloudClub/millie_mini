import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_provider.dart';
import '../utils/constants.dart';
import '../services/custom_face_service.dart';
import '../models/custom_face.dart';

/// Face generator page for creating custom AI faces
class FaceGeneratorPage extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(CustomFace face) onFaceSaved;

  const FaceGeneratorPage({
    super.key,
    required this.onBack,
    required this.onFaceSaved,
  });

  @override
  State<FaceGeneratorPage> createState() => _FaceGeneratorPageState();
}

class _FaceGeneratorPageState extends State<FaceGeneratorPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isGenerating = false;
  bool _isRecording = false;
  bool _isSaving = false;
  String? _generatedImageUrl;
  String? _generatedDescription;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final voiceProvider = context.read<VoiceProvider>();
    final path = await voiceProvider.startTranscriptionRecording();
    if (path != null) {
      setState(() {
        _isRecording = true;
      });

      // Auto-stop after 20 seconds
      Future.delayed(const Duration(seconds: 20), () {
        if (_isRecording) {
          _stopRecording();
        }
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    final voiceProvider = context.read<VoiceProvider>();
    setState(() {
      _isRecording = false;
      _textController.text = "Transcribing...";
    });

    final transcription = await voiceProvider.stopAndTranscribe();
    if (transcription != null && transcription.isNotEmpty) {
      setState(() {
        _textController.text = transcription;
      });
    } else {
      setState(() {
        _textController.clear();
      });
    }
  }

  Future<void> _generateFace() async {
    // Stop recording if active
    if (_isRecording) {
      await _stopRecording();
    }

    final description = _textController.text.trim();
    if (description.isEmpty || description == "Transcribing...") return;

    // Hide keyboard
    _focusNode.unfocus();

    setState(() {
      _isGenerating = true;
      _generatedImageUrl = null;
    });

    final imageUrl = await CustomFaceService.generateFace(description);

    if (mounted) {
      setState(() {
        _isGenerating = false;
        _generatedImageUrl = imageUrl;
        _generatedDescription = description;
      });
    }
  }

  Future<void> _saveFace() async {
    if (_generatedImageUrl == null || _generatedDescription == null) return;

    setState(() {
      _isSaving = true;
    });

    final face = await CustomFaceService.saveFace(
      imageUrl: _generatedImageUrl!,
      description: _generatedDescription!,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
      });

      if (face != null) {
        widget.onFaceSaved(face);
      }
    }
  }

  void _clearPreview() {
    setState(() {
      _generatedImageUrl = null;
      _generatedDescription = null;
      _textController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(),

            // Preview area
            Expanded(
              child: _buildPreviewArea(),
            ),

            // Bottom input bar
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // Back button (green)
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          // Title
          const Expanded(
            child: Text(
              'Create Face',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          // Save button (blue) - only visible when image is generated
          if (_generatedImageUrl != null)
            GestureDetector(
              onTap: _isSaving ? null : _saveFace,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isSaving ? Colors.grey : Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.save_alt,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
            )
          else
            const SizedBox(width: 44), // Spacer for alignment
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.75, // Portrait orientation (3:4)
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: _buildPreviewContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (_isGenerating) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Generating face...',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (_generatedImageUrl != null) {
      return Stack(
        children: [
          Image.network(
            _generatedImageUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Failed to load image',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Clear button in bottom left
          Positioned(
            bottom: 8,
            left: 8,
            child: GestureDetector(
              onTap: _clearPreview,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Try Again',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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

    // Empty state
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.face,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Describe your face below',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'e.g., "a friendly blue robot"\nor "a cute orange cat"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _textController.text.isNotEmpty &&
        _textController.text != "Transcribing...";
    final canSend = (hasText || _isRecording) && !_isGenerating;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mic button (left)
          GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red : Colors.grey.shade700,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Text input
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !_isRecording && !_isGenerating,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  minLines: 1,
                  maxLines: 3,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: _isRecording
                        ? '🔴 Recording...'
                        : 'Describe your face...',
                    hintStyle: TextStyle(
                      color: _isRecording
                          ? Colors.red.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _generateFace(),
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Generate/Send button (right)
          GestureDetector(
            onTap: canSend ? _generateFace : null,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: canSend ? Colors.white : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send,
                color: canSend ? Colors.black : Colors.white54,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
