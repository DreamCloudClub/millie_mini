import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';

/// Chat input states
enum ChatInputState {
  empty,      // No text, show record button
  recording,  // Recording, show stop + send
  hasText,    // Has text, show send button
}

/// Chat/Image/Translate mode toggle
enum ChatMode {
  text,
  image,
  translate,
}

class ChatPage extends StatefulWidget {
  final VoidCallback onNavigateToFace;
  final VoidCallback? onRefresh;

  const ChatPage({
    super.key,
    required this.onNavigateToFace,
    this.onRefresh,
  });

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> with AutomaticKeepAliveClientMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  ChatMode _mode = ChatMode.text;
  ChatInputState _inputState = ChatInputState.empty;
  bool _isMuted = false;
  bool _hasStartedConversation = false;
  bool _isGeneratingImage = false;
  
  // Image mode state - conversation-like structure
  final List<_ImageConversationItem> _imageConversation = [];
  File? _selectedImage; // Reference image ready to send
  String? _currentImagePrompt; // Current prompt being generated
  final ImagePicker _imagePicker = ImagePicker();

  // Translate mode state
  String _languageA = 'English';
  String _languageB = 'Spanish';
  final List<_TranslationItem> _translationConversation = [];
  bool _isTranslating = false;

  static const List<String> _supportedLanguages = [
    'English',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Portuguese',
    'Chinese',
    'Japanese',
    'Korean',
    'Arabic',
    'Russian',
    'Hindi',
  ];

  @override
  bool get wantKeepAlive => true; // Preserve state when swiping between pages
  
  /// Switch to image mode (called from external navigation)
  void switchToImageMode() {
    debugPrint('ChatPage: Switching to image mode');
    setState(() {
      _mode = ChatMode.image;
    });
  }
  
  /// Switch to text mode (called from external navigation)
  void switchToTextMode() {
    debugPrint('ChatPage: Switching to text mode');
    setState(() {
      _mode = ChatMode.text;
    });
  }

  int _lastMessageCount = 0;
  
  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    
    // Check if conversation already has messages and set up listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final voiceProvider = context.read<VoiceProvider>();
      if (voiceProvider.conversation != null && 
          voiceProvider.conversation!.messages.isNotEmpty) {
        setState(() {
          _hasStartedConversation = true;
        });
        _lastMessageCount = voiceProvider.conversation!.messages.length;
      }
      
      // Listen for new messages to auto-scroll
      voiceProvider.addListener(_onVoiceProviderChanged);
    });
  }
  
  void _onVoiceProviderChanged() {
    final voiceProvider = context.read<VoiceProvider>();
    final currentCount = voiceProvider.conversation?.messages.length ?? 0;
    
    // If message count increased, scroll to bottom
    if (currentCount > _lastMessageCount) {
      _lastMessageCount = currentCount;
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    // Remove voice provider listener
    try {
      context.read<VoiceProvider>().removeListener(_onVoiceProviderChanged);
    } catch (_) {
      // Context may not be available during dispose
    }
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      if (_textController.text.isNotEmpty) {
        _inputState = ChatInputState.hasText;
      } else if (_inputState != ChatInputState.recording) {
        _inputState = ChatInputState.empty;
      }
    });
  }

  void _onFocusChanged() {
    // When keyboard opens/closes, we may want to update UI
    setState(() {});
  }

  void _toggleMode(ChatMode mode) {
    setState(() {
      _mode = mode;
      // Clear text when switching modes
      _textController.clear();
      _inputState = ChatInputState.empty;
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  Future<void> _startRecording() async {
    final voiceProvider = context.read<VoiceProvider>();
    
    final path = await voiceProvider.startTranscriptionRecording();
    if (path != null) {
      setState(() {
        _inputState = ChatInputState.recording;
      });
      debugPrint('Started recording: $path');
      
      // Auto-stop after 20 seconds
      Future.delayed(const Duration(seconds: 20), () {
        if (_inputState == ChatInputState.recording) {
          _stopRecording();
        }
      });
    } else {
      debugPrint('Failed to start recording');
    }
  }

  Future<void> _stopRecording() async {
    if (_inputState != ChatInputState.recording) return;

    final voiceProvider = context.read<VoiceProvider>();

    setState(() {
      _inputState = ChatInputState.hasText;
      _textController.text = "Transcribing...";
    });

    // For translate mode, use auto-detect (null) so Whisper keeps original language
    // For other modes, use English
    final transcription = await voiceProvider.stopAndTranscribe(
      language: _mode == ChatMode.translate ? null : 'en',
    );

    if (transcription != null && transcription.isNotEmpty) {
      setState(() {
        _textController.text = transcription;
      });
      debugPrint('Transcription complete: $transcription');
    } else {
      setState(() {
        _textController.clear();
        _inputState = ChatInputState.empty;
      });
      debugPrint('No transcription received');
    }
  }

  Future<void> _sendMessage() async {
    // If still recording, stop and transcribe first
    if (_inputState == ChatInputState.recording) {
      await _stopRecording();
    }

    // Now check if we have text to send
    final messageText = _textController.text.trim();
    if (messageText.isEmpty || messageText == "Transcribing...") return;

    setState(() {
      _hasStartedConversation = true;
      _textController.clear();
      _inputState = ChatInputState.empty;
    });

    // Hide keyboard
    _focusNode.unfocus();

    if (_mode == ChatMode.text) {
      final voiceProvider = context.read<VoiceProvider>();

      // Send text message (this adds to conversation and calls LLM)
      await voiceProvider.sendTextMessage(
        text: messageText,
        playAudio: !_isMuted,
      );

      // Scroll to bottom
      _scrollToBottom();
    } else if (_mode == ChatMode.image) {
      // Image mode - generate image
      await _generateImage(messageText);
    } else {
      // Translate mode
      await _translateAndSpeak(messageText);
    }
  }
  
  Future<void> _generateImage(String prompt) async {
    // Capture the reference image before clearing it
    final referenceImage = _selectedImage;
    
    setState(() {
      _isGeneratingImage = true;
      _currentImagePrompt = prompt;
      // Add user prompt to conversation
      _imageConversation.add(_ImageConversationItem.userPrompt(
        prompt, 
        referenceImage: referenceImage,
      ));
      _selectedImage = null; // Clear reference image after adding to conversation
      _hasStartedConversation = true;
    });
    
    // Scroll to bottom to show the new prompt
    _scrollToBottom();
    
    try {
      // Get OpenAI service
      final storageService = StorageService();
      await storageService.init();
      final openaiService = OpenAIService(storageService);
      
      // Get previous prompt for context (helps maintain style continuity)
      String? previousPrompt;
      for (int i = _imageConversation.length - 2; i >= 0; i--) {
        if (_imageConversation[i].isUser && _imageConversation[i].text != null) {
          previousPrompt = _imageConversation[i].text;
          break;
        }
      }
      
      // Generate image with optional reference image and previous context
      final imageUrl = await openaiService.generateImage(
        prompt: prompt,
        referenceImage: referenceImage,
        previousPrompt: previousPrompt,
      );
      
      if (imageUrl != null) {
        setState(() {
          // Add AI image response to conversation
          _imageConversation.add(_ImageConversationItem.aiImage(imageUrl));
        });
        debugPrint('Image generated: $imageUrl');
        _scrollToBottom();
        // Scroll again after image likely loads
        Future.delayed(const Duration(milliseconds: 500), _scrollToBottom);
      } else {
        debugPrint('Failed to generate image');
      }
    } catch (e) {
      debugPrint('Error generating image: $e');
    } finally {
      setState(() {
        _isGeneratingImage = false;
        _currentImagePrompt = null;
      });
    }
  }

  Future<void> _translateAndSpeak(String text) async {
    setState(() {
      _isTranslating = true;
      _hasStartedConversation = true;
    });
    _scrollToBottom();

    try {
      final storageService = StorageService();
      await storageService.init();
      final openaiService = OpenAIService(storageService);

      // Detect which language the input is in and translate to the other
      final detectedLanguage = await openaiService.detectLanguage(text, [_languageA, _languageB]);
      final targetLanguage = detectedLanguage == _languageA ? _languageB : _languageA;

      // Translate the text
      final translatedText = await openaiService.translateText(
        text: text,
        targetLanguage: targetLanguage,
      );

      if (translatedText != null) {
        // Add to conversation
        setState(() {
          _translationConversation.add(_TranslationItem(
            originalText: text,
            originalLanguage: detectedLanguage,
            translatedText: translatedText,
            translatedLanguage: targetLanguage,
          ));
        });
        _scrollToBottom();

        // Speak the translation using TTS
        if (mounted) {
          final voice = _getVoiceForLanguage(targetLanguage);
          final voiceProvider = context.read<VoiceProvider>();
          await voiceProvider.speakText(translatedText, voice: voice);
        }
      }
    } catch (e) {
      debugPrint('Error translating: $e');
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  String _getVoiceForLanguage(String language) {
    // Map languages to appropriate OpenAI TTS voices
    switch (language.toLowerCase()) {
      case 'spanish':
      case 'italian':
      case 'portuguese':
        return 'nova'; // Good for Romance languages
      case 'french':
        return 'shimmer';
      case 'german':
        return 'onyx';
      case 'japanese':
      case 'korean':
      case 'chinese':
        return 'nova';
      default:
        return 'alloy'; // Default English voice
    }
  }

  void _openCamera() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.faceBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
  
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _hasStartedConversation = true;
        });
        debugPrint('Image selected: ${pickedFile.path}');
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _scrollToBottom() {
    // Use a slight delay to ensure content is laid out before scrolling
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: AppColors.faceBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with navigation and toggle
            _buildTopBar(),
            
            // Main content area with persistent rounded container
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: _mode == ChatMode.text
                      ? Consumer<VoiceProvider>(
                          builder: (context, voiceProvider, _) {
                            final hasMessages = voiceProvider.conversation?.messages.isNotEmpty ?? false;
                            return hasMessages
                                ? _buildChatView()
                                : _buildInitialView();
                          },
                        )
                      : _mode == ChatMode.image
                          ? Builder(
                              builder: (context) {
                                final hasContent = _imageConversation.isNotEmpty || _selectedImage != null;
                                return hasContent
                                    ? _buildImageView()
                                    : _buildInitialView();
                              },
                            )
                          : Builder(
                              builder: (context) {
                                // Translate mode
                                return _translationConversation.isNotEmpty
                                    ? _buildTranslateView()
                                    : _buildInitialView();
                              },
                            ),
                ),
              ),
            ),
            
            // Input bar at bottom
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
          // Refresh button (left) - green
          _NavigationButton(
            icon: Icons.refresh,
            onTap: _handleRefresh,
            backgroundColor: Colors.green,
            iconColor: Colors.white,
          ),
          
          const Spacer(),
          
          // Mode toggle (center)
          _ModeToggle(
            currentMode: _mode,
            onModeChanged: _toggleMode,
          ),
          
          const Spacer(),
          
          // Back to Face (right arrow) - orange
          _NavigationButton(
            icon: Icons.arrow_forward,
            onTap: widget.onNavigateToFace,
            backgroundColor: AppColors.primaryOrange,
            iconColor: Colors.white,
          ),
        ],
      ),
    );
  }
  
  void _handleRefresh() {
    if (_mode == ChatMode.image) {
      // Image mode: Only clear image conversation (independent context)
      setState(() {
        _imageConversation.clear();
        _selectedImage = null;
        _currentImagePrompt = null;
        _textController.clear();
        _inputState = ChatInputState.empty;
      });
      debugPrint('Image mode refresh: Cleared image conversation only');
    } else if (_mode == ChatMode.translate) {
      // Translate mode: Clear translation conversation
      setState(() {
        _translationConversation.clear();
        _hasStartedConversation = false;
        _textController.clear();
        _inputState = ChatInputState.empty;
      });
      debugPrint('Translate mode refresh: Cleared translation conversation');
    } else {
      // Text mode: Clear text input and refresh voice/text conversation
      setState(() {
        _hasStartedConversation = false;
        _textController.clear();
        _inputState = ChatInputState.empty;
      });
      // Call parent refresh to clear voice conversation (synced with face page)
      widget.onRefresh?.call();
      debugPrint('Text mode refresh: Cleared text/voice conversation');
    }
  }

  Widget _buildInitialView() {
    String title;
    String subtitle;
    IconData fallbackIcon;

    switch (_mode) {
      case ChatMode.text:
        title = 'AI Chat Bot';
        subtitle = 'How can I help you?';
        fallbackIcon = Icons.chat;
        break;
      case ChatMode.image:
        title = 'AI Artist';
        subtitle = 'What can I create for you?';
        fallbackIcon = Icons.palette;
        break;
      case ChatMode.translate:
        title = 'AI Translator';
        subtitle = 'Speak in either language';
        fallbackIcon = Icons.translate;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Millie logo/icon with white border
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Image.asset(
                'assets/icon/icon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(fallbackIcon, size: 60, color: Colors.white);
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Title
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Subtitle
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              color: Colors.white.withOpacity(0.6),
            ),
          ),

          // Language selectors for translate mode
          if (_mode == ChatMode.translate) ...[
            const SizedBox(height: AppSpacing.xl),
            _buildLanguageSelectors(),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageSelectors() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Language A dropdown
        _buildLanguageDropdown(
          value: _languageA,
          onChanged: (lang) => setState(() => _languageA = lang!),
        ),
        const SizedBox(width: AppSpacing.md),
        // Swap button
        GestureDetector(
          onTap: () {
            setState(() {
              final temp = _languageA;
              _languageA = _languageB;
              _languageB = temp;
            });
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.swap_horiz, color: Colors.white),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // Language B dropdown
        _buildLanguageDropdown(
          value: _languageB,
          onChanged: (lang) => setState(() => _languageB = lang!),
        ),
      ],
    );
  }

  Widget _buildLanguageDropdown({
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: value,
        dropdownColor: const Color(0xFF2A2A2A),
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          color: Colors.white,
          fontSize: 14,
        ),
        underline: const SizedBox(),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
        items: _supportedLanguages.map((lang) {
          return DropdownMenuItem(value: lang, child: Text(lang));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildConversationView() {
    if (_mode == ChatMode.text) {
      return _buildChatView();
    } else {
      return _buildImageView();
    }
  }

  Widget _buildChatView() {
    return Consumer<VoiceProvider>(
      builder: (context, voiceProvider, _) {
        final messages = voiceProvider.conversation?.messages ?? [];
        
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md + 16, // Extra bottom padding to appear above rounded border
          ),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isUser = message.role == MessageRole.user;
            
            return _ChatBubble(
              message: message.content,
              isUser: isUser,
            );
          },
        );
      },
    );
  }

  Widget _buildImageView() {
    // Build list of items to display (conversation + pending reference image + loading)
    final List<Widget> items = [];
    
    // Add conversation items
    for (final item in _imageConversation) {
      if (item.isUser) {
        // User prompt - right-aligned bubble with optional reference image
        items.add(_buildUserPromptBubble(item.text ?? '', item.referenceImage));
      } else {
        // AI image response - full width
        items.add(_buildGeneratedImage(item.imageUrl!));
      }
    }
    
    // Show loading indicator if generating
    if (_isGeneratingImage) {
      items.add(_buildImageLoadingIndicator());
    }
    
    // Show pending reference image (user is composing a prompt)
    if (_selectedImage != null && !_isGeneratingImage) {
      items.add(_buildPendingReferenceImage());
    }
    
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Your generated images will appear here',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 16,
          ),
        ),
      );
    }
    
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: items,
    );
  }

  Widget _buildTranslateView() {
    return Column(
      children: [
        // Language selectors at top
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _buildLanguageSelectors(),
        ),
        // Translation conversation
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: _translationConversation.length + (_isTranslating ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _translationConversation.length && _isTranslating) {
                return _buildTranslatingIndicator();
              }
              final item = _translationConversation[index];
              return _buildTranslationBubble(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTranslationBubble(_TranslationItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Original text (right-aligned, grey)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: const Color(0xFF4A4A4A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.originalLanguage,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.originalText,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Translated text (left-aligned, blue border)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.blue, width: 1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.translatedLanguage,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.translatedText,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslatingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  /// Build a user prompt bubble (right-aligned) with optional reference image
  Widget _buildUserPromptBubble(String text, File? referenceImage) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt text bubble (right-aligned)
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF4A4A4A), // Medium grey
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Reference image thumbnail if present
                  if (referenceImage != null) ...[
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          referenceImage,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  // Prompt text
                  Text(
                    text,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build a generated image (full width, square aspect ratio for DALL-E)
  Widget _buildGeneratedImage(String imageUrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.0, // DALL-E generates square images
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    // Image loaded - scroll to show it
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                    return child;
                  }
                  return Container(
                    color: Colors.white.withOpacity(0.1),
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.white.withOpacity(0.1),
                    child: const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  );
                },
              ),
            ),
            // Save button in upper right corner
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _saveImage(imageUrl),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.save_alt,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Save image to device gallery
  Future<void> _saveImage(String imageUrl) async {
    try {
      // Show saving indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saving image...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Download image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image');
      }

      // Save to temp file first
      final tempDir = await getTemporaryDirectory();
      final fileName = 'millie_image_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      // Save to gallery
      await Gal.putImage(tempFile.path, album: 'Millie Mini');

      // Clean up temp file
      await tempFile.delete();

      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Build loading indicator while generating image
  Widget _buildImageLoadingIndicator() {
    return Container(
      height: 200,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Generating image...',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build pending reference image (shown when user is composing)
  Widget _buildPendingReferenceImage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                _selectedImage!,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, // Align buttons to bottom
        children: [
          // Left button (mute/camera/stop)
          _buildLeftButton(),
          
          const SizedBox(width: AppSpacing.sm),
          
          // Text input field
          Expanded(
            child: _buildTextField(),
          ),
          
          const SizedBox(width: AppSpacing.sm),
          
          // Right button (record/send)
          _buildRightButton(),
        ],
      ),
    );
  }

  Widget _buildLeftButton() {
    if (_inputState == ChatInputState.recording) {
      // Stop button during recording - grey style like nav buttons
      return _InputButton(
        icon: Icons.stop,
        onTap: _stopRecording,
        backgroundColor: Colors.white.withOpacity(0.1),
        iconColor: Colors.white,
      );
    }
    
    if (_mode == ChatMode.text) {
      // Mute button for text mode - dark grey like search bar X button
      return _InputButton(
        icon: _isMuted ? Icons.volume_off : Icons.volume_up,
        onTap: _toggleMute,
        backgroundColor: Colors.grey.shade700,
        iconColor: Colors.white,
      );
    } else {
      // Camera button for image mode - dark grey like search bar X button
      return _InputButton(
        icon: Icons.camera_alt,
        onTap: _openCamera,
        backgroundColor: Colors.grey.shade700,
        iconColor: Colors.white,
      );
    }
  }

  Widget _buildTextField() {
    String placeholder;
    if (_inputState == ChatInputState.recording) {
      placeholder = '🔴 Recording...';
    } else if (_mode == ChatMode.text || _mode == ChatMode.translate) {
      placeholder = 'Type or speak...';
    } else {
      placeholder = 'Describe your image...';
    }

    return Container(
      constraints: const BoxConstraints(
        minHeight: 48, // Match button height exactly
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          enabled: _inputState != ChatInputState.recording,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
          minLines: 1,
          maxLines: 10,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(
              color: _inputState == ChatInputState.recording 
                  ? Colors.red.withOpacity(0.8)
                  : Colors.white.withOpacity(0.5),
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
            ),
          ),
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
        ),
      ),
    );
  }

  Widget _buildRightButton() {
    if (_inputState == ChatInputState.empty) {
      // Record button when empty - white with black icon
      return _InputButton(
        icon: Icons.mic,
        onTap: _startRecording,
      );
    } else {
      // Send button when has text or recording - white with black icon
      return _InputButton(
        icon: Icons.send,
        onTap: _sendMessage,
      );
    }
  }
}

/// Navigation button for top bar
class _NavigationButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;

  const _NavigationButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

/// Mode toggle switch
class _ModeToggle extends StatelessWidget {
  final ChatMode currentMode;
  final ValueChanged<ChatMode> onModeChanged;

  const _ModeToggle({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleOption(
            icon: Icons.chat_bubble_outline,
            label: 'Text',
            isSelected: currentMode == ChatMode.text,
            onTap: () => onModeChanged(ChatMode.text),
          ),
          const SizedBox(width: 4),
          _ToggleOption(
            icon: Icons.palette_outlined,
            label: 'Image',
            isSelected: currentMode == ChatMode.image,
            onTap: () => onModeChanged(ChatMode.image),
          ),
          const SizedBox(width: 4),
          _ToggleOption(
            icon: Icons.translate,
            label: 'Translate',
            isSelected: currentMode == ChatMode.translate,
            onTap: () => onModeChanged(ChatMode.translate),
          ),
        ],
      ),
    );
  }
}

/// Individual toggle option
class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Input button (customizable colors)
class _InputButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;

  const _InputButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.black,
          size: 24,
        ),
      ),
    );
  }
}

/// Chat message bubble
class _ChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;

  const _ChatBubble({
    required this.message,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: isUser 
              ? const Color(0xFF4A4A4A)  // Medium grey bubble for user
              : Colors.black,             // Black bubble for AI
          border: isUser 
              ? null 
              : Border.all(color: Colors.blue, width: 1),  // Blue border for AI
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Represents an item in the image generation conversation
class _ImageConversationItem {
  final bool isUser; // true = user prompt, false = AI image response
  final String? text; // User's prompt text
  final String? imageUrl; // Generated image URL (for AI responses)
  final File? referenceImage; // Reference image attached to user prompt

  const _ImageConversationItem({
    required this.isUser,
    this.text,
    this.imageUrl,
    this.referenceImage,
  });

  /// Create a user prompt item
  factory _ImageConversationItem.userPrompt(String text, {File? referenceImage}) {
    return _ImageConversationItem(
      isUser: true,
      text: text,
      referenceImage: referenceImage,
    );
  }

  /// Create an AI image response item
  factory _ImageConversationItem.aiImage(String imageUrl) {
    return _ImageConversationItem(
      isUser: false,
      imageUrl: imageUrl,
    );
  }
}

/// Represents a translation item
class _TranslationItem {
  final String originalText;
  final String originalLanguage;
  final String translatedText;
  final String translatedLanguage;

  const _TranslationItem({
    required this.originalText,
    required this.originalLanguage,
    required this.translatedText,
    required this.translatedLanguage,
  });
}

