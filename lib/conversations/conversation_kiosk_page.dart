import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/openai_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/text_helpers.dart';
import '../widgets/widgets.dart';

/// Dedicated kiosk page for running scripted conversations
class ConversationKioskPage extends StatefulWidget {
  final String templateId;
  final VoidCallback onExit;

  const ConversationKioskPage({
    super.key,
    required this.templateId,
    required this.onExit,
  });

  @override
  State<ConversationKioskPage> createState() => _ConversationKioskPageState();
}

enum KioskState {
  welcome,              // Showing welcome screen with Start button
  speaking,             // Millie is speaking the prompt
  listening,            // Waiting for user response
  processing,           // Processing the audio response
  confirming,           // AI is confirming/following up (speaking)
  listeningConfirm,     // Listening for yes/no after confirmation
  reviewSpeaking,       // Speaking "Does everything look correct?"
  reviewListening,      // Listening for confirmation/edits
  reviewProcessing,     // Processing their review response
  complete,             // Final thank you - ready for next person
}

class _ConversationKioskPageState extends State<ConversationKioskPage> {
  ConversationTemplate? _template;
  int _currentStepIndex = 0;
  KioskState _state = KioskState.welcome;

  // Collected responses
  final Map<String, String> _responses = {};

  // Current response being captured
  String _currentResponse = '';
  String _aiConfirmation = '';

  // TTS
  late final OpenAIService _openAIService;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentVoice = 'alloy';

  // STT / Recording
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _amplitudeTimer;
  Timer? _silenceTimer;
  DateTime? _lastSpeechTime;
  bool _speechDetected = false;
  static const Duration _silenceThreshold = Duration(milliseconds: 1500);
  static const double _speechThreshold = -35.0; // dB threshold for speech

  @override
  void initState() {
    super.initState();
    _initServices();
    _loadTemplate();
  }

  void _initServices() {
    final storageService = StorageService();
    _openAIService = OpenAIService(storageService);

    // Get voice from active agent
    final agentProvider = context.read<AgentProvider>();
    final activeAgent = agentProvider.activeAgent;
    if (activeAgent != null) {
      _currentVoice = activeAgent.voice;
    }

    // Listen for audio completion
    _audioPlayer.onPlayerComplete.listen((_) {
      _onSpeakingComplete();
    });
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _silenceTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _loadTemplate() {
    final provider = context.read<ConversationTemplateProvider>();
    setState(() {
      _template = provider.getTemplateById(widget.templateId);
    });
  }

  ConversationStep? get _currentStep {
    if (_template == null || _currentStepIndex >= _template!.steps.length) {
      return null;
    }
    return _template!.steps[_currentStepIndex];
  }

  void _handleStart() {
    setState(() {
      _state = KioskState.speaking;
      _currentStepIndex = 0;
      _responses.clear();
    });

    _speakCurrentStep();
  }

  Future<void> _speakCurrentStep() async {
    final step = _currentStep;
    if (step == null) return;

    await _speakText(step.prompt);
  }

  Future<void> _speakText(String text) async {
    try {
      debugPrint('Speaking: $text');
      final audioPath = await _openAIService.textToSpeech(
        text: text,
        voice: _currentVoice,
        model: 'tts-1',
      );

      if (audioPath != null && mounted) {
        await _audioPlayer.play(DeviceFileSource(audioPath));
      } else {
        // TTS failed, proceed anyway
        _onSpeakingComplete();
      }
    } catch (e) {
      debugPrint('TTS error: $e');
      _onSpeakingComplete();
    }
  }

  void _onSpeakingComplete() {
    if (!mounted) return;

    // Handle review speaking (no step needed)
    if (_state == KioskState.reviewSpeaking) {
      _handleReviewSpeakingComplete();
      return;
    }

    // Handle complete state (thank you message spoken)
    if (_state == KioskState.complete) {
      // Auto-restart after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _state == KioskState.complete) {
          _handleRestart();
        }
      });
      return;
    }

    final step = _currentStep;
    if (step == null) return;

    if (_state == KioskState.speaking) {
      if (step.capturesResponse) {
        setState(() {
          _state = KioskState.listening;
          _currentResponse = '';
        });
        _startListening();
      } else {
        // No response needed, move to next step
        _moveToNextStep();
      }
    } else if (_state == KioskState.confirming) {
      // Confirmation speech done, now listen for yes/no
      setState(() {
        _state = KioskState.listeningConfirm;
      });
      _startListening();
    }
  }

  Future<void> _startListening() async {
    // Cancel any existing timers first
    _amplitudeTimer?.cancel();
    _silenceTimer?.cancel();

    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('No microphone permission');
        return;
      }

      // Stop any existing recording
      try {
        await _recorder.stop();
      } catch (_) {}

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/kiosk_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      debugPrint('Started recording: $path');

      // Reset speech detection state
      _speechDetected = false;
      _lastSpeechTime = null;

      // Monitor amplitude for silence detection
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
        final isListening = _state == KioskState.listening ||
            _state == KioskState.listeningConfirm ||
            _state == KioskState.reviewListening;
        if (!mounted || !isListening) {
          timer.cancel();
          return;
        }

        try {
          final amplitude = await _recorder.getAmplitude();
          final db = amplitude.current;

          if (db > _speechThreshold) {
            // Speech detected
            _speechDetected = true;
            _lastSpeechTime = DateTime.now();
          }
        } catch (e) {
          debugPrint('Amplitude error: $e');
        }
      });

      // Monitor for silence after speech
      _silenceTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
        final isListening = _state == KioskState.listening ||
            _state == KioskState.listeningConfirm ||
            _state == KioskState.reviewListening;
        if (!mounted || !isListening) {
          timer.cancel();
          return;
        }

        if (_speechDetected && _lastSpeechTime != null) {
          final silenceDuration = DateTime.now().difference(_lastSpeechTime!);
          if (silenceDuration >= _silenceThreshold) {
            debugPrint('Silence detected after ${silenceDuration.inMilliseconds}ms - stopping');
            timer.cancel();
            _amplitudeTimer?.cancel();
            await _stopListeningAndTranscribe();
          }
        }
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopListeningAndTranscribe() async {
    // Cancel timers
    _amplitudeTimer?.cancel();
    _silenceTimer?.cancel();

    // Save current state before changing to processing
    final previousState = _state;
    final wasConfirming = previousState == KioskState.listeningConfirm;
    final wasReviewing = previousState == KioskState.reviewListening;

    KioskState getReturnState() {
      if (wasReviewing) return KioskState.reviewListening;
      if (wasConfirming) return KioskState.listeningConfirm;
      return KioskState.listening;
    }

    try {
      final path = await _recorder.stop();
      debugPrint('Stopped recording: $path');

      if (path == null) {
        // Recording failed, go back to listening
        setState(() {
          _state = getReturnState();
        });
        _startListening();
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        debugPrint('Recording file not found');
        setState(() {
          _state = getReturnState();
        });
        _startListening();
        return;
      }

      // Transcribe with Whisper
      setState(() {
        _state = wasReviewing ? KioskState.reviewProcessing : KioskState.processing;
      });

      final transcription = await _openAIService.speechToText(path);

      if (transcription != null && transcription.isNotEmpty && mounted) {
        if (wasReviewing) {
          _handleReviewResponse(transcription);
        } else if (wasConfirming) {
          _handleConfirmationResponse(transcription);
        } else {
          _handleResponseReceived(transcription);
        }
      } else {
        // No transcription, go back to listening
        setState(() {
          _state = getReturnState();
          _currentResponse = '';
        });
        _startListening();
      }

      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      // On error, try to recover by going back to listening
      if (mounted) {
        setState(() {
          _state = getReturnState();
        });
        _startListening();
      }
    }
  }

  Future<void> _handleConfirmationResponse(String response) async {
    final step = _currentStep;
    if (step == null) return;

    // For structured data types OR explicitSpelling, use smarter AI handling
    final needsAIHandling = step.slotType == SlotType.name ||
        step.slotType == SlotType.datetime ||
        step.slotType == SlotType.address ||
        step.collectsPhoneNumber ||
        step.confirmationType == ConfirmationType.explicitSpelling;

    if (needsAIHandling) {
      await _handleStructuredDataConfirmation(step, response);
      return;
    }

    // Use LLM to interpret the follow-up response
    final prompt = '''You are interpreting a user's response during a voice intake form.

The question was: "${step.prompt}"
Their initial answer was: "$_currentResponse"
After confirmation, they said: "$response"

Determine the intent. Respond with ONLY one of these exact words:
- CONFIRMED (they agreed, said yes, that's correct, that's all, etc.)
- CORRECTION (they're correcting or replacing their answer)
- ADDITION (they're adding more information to their answer)

Just respond with the single word.''';

    try {
      final result = await _openAIService.callChatCompletions(
        systemPrompt: 'You interpret user responses during voice intake forms. Respond with a single word only.',
        conversationHistory: [],
        userMessage: prompt,
        model: 'gpt-4o-mini',
      );

      final intentLower = (result?.content ?? 'confirmed').toLowerCase().trim();

      if (intentLower.contains('confirmed')) {
        _moveToNextStep();
      } else if (intentLower.contains('correction')) {
        // Replace the response with the new one
        setState(() {
          _currentResponse = response;
        });
        if (step.slotName != null) {
          _responses[step.slotName!] = response;
        }
        // Confirm the correction
        _generateConfirmation(step, response);
      } else if (intentLower.contains('addition')) {
        // Append to the response
        final combined = '$_currentResponse. $response';
        setState(() {
          _currentResponse = combined;
        });
        if (step.slotName != null) {
          _responses[step.slotName!] = combined;
        }
        // Confirm the addition
        _generateConfirmation(step, combined);
      } else {
        // Default to confirmed
        _moveToNextStep();
      }
    } catch (e) {
      debugPrint('Error interpreting confirmation: $e');
      // Default to move on
      _moveToNextStep();
    }
  }

  /// Handle confirmation responses for structured data (name, date, address) with AI
  Future<void> _handleStructuredDataConfirmation(ConversationStep step, String response) async {
    setState(() {
      _state = KioskState.processing;
    });

    String dataTypeLabel;
    switch (step.slotType) {
      case SlotType.name:
        dataTypeLabel = 'name';
        break;
      case SlotType.datetime:
        dataTypeLabel = 'date/time';
        break;
      case SlotType.address:
        dataTypeLabel = 'address';
        break;
      case SlotType.phone:
        dataTypeLabel = 'phone number';
        break;
      case SlotType.simple:
      case SlotType.freeform:
      case SlotType.none:
        dataTypeLabel = step.collectsPhoneNumber ? 'phone number' : 'information';
        break;
    }

    try {
      final result = await _openAIService.callChatCompletions(
        systemPrompt: 'You interpret user responses about data confirmation. You must return the COMPLETE corrected value, not just the correction.',
        conversationHistory: [],
        userMessage: '''The user was confirming this $dataTypeLabel: "$_currentResponse"
They responded: "$response"

Determine what they mean and respond with EXACTLY one of these formats:
- CONFIRMED (if they said yes, correct, that's right, looks good, etc.)
- CORRECTION|[full_corrected_value] (apply their correction and return the COMPLETE corrected $dataTypeLabel)
- ADDITION|[full_value_with_addition] (add to the existing value and return the COMPLETE $dataTypeLabel)
- REPLACEMENT|[completely_new_value] (they're giving a completely different $dataTypeLabel)

IMPORTANT: Always return the FULL value after applying corrections, not just the changed part.

Examples for name "John Smithe":
- "Yes" → CONFIRMED
- "No, S-M-I-T-H" → CORRECTION|John Smith (full name with correction applied)
- "It ends with just H, no E" → CORRECTION|John Smith (full corrected name)
- "Actually it's Jon, no H" → CORRECTION|Jon Smithe (full name with first name corrected)
- "Add my middle name, Michael" → ADDITION|John Michael Smithe

Examples for name "Nicolas":
- "It's Nicolac with a C at the end" → CORRECTION|Nicolac (full corrected name)
- "Nicholas with an H" → CORRECTION|Nicholas (full corrected name)

Respond with ONLY the format above, nothing else.''',
        model: 'gpt-4o-mini',
      );

      final resultText = (result?.content ?? 'CONFIRMED').trim();

      if (resultText.startsWith('CONFIRMED')) {
        _moveToNextStep();
      } else if (resultText.contains('|')) {
        final parts = resultText.split('|');
        final newValue = parts.length > 1 ? parts[1].trim() : _currentResponse;

        // Clean the new value with AI to ensure proper formatting
        final cleanedValue = await _extractDataWithAI(newValue, step);

        setState(() {
          _currentResponse = cleanedValue;
        });
        if (step.slotName != null) {
          _responses[step.slotName!] = cleanedValue;
        }

        // Ask for confirmation again
        _generateAIConfirmation(step, cleanedValue);
      } else {
        // Default to confirmed
        _moveToNextStep();
      }
    } catch (e) {
      debugPrint('Error interpreting confirmation: $e');
      _moveToNextStep();
    }
  }

  Future<void> _handleResponseReceived(String response) async {
    final step = _currentStep;
    if (step == null) return;

    // For structured data types OR explicitSpelling confirmation, use AI extraction
    final needsAIExtraction = step.slotType == SlotType.name ||
        step.slotType == SlotType.datetime ||
        step.slotType == SlotType.address ||
        step.collectsPhoneNumber ||
        step.confirmationType == ConfirmationType.explicitSpelling;

    if (needsAIExtraction) {
      setState(() {
        _state = KioskState.processing;
      });

      final cleanedValue = await _extractDataWithAI(response, step);

      setState(() {
        _currentResponse = cleanedValue;
      });

      if (step.slotName != null) {
        _responses[step.slotName!] = cleanedValue;
      }

      if (step.confirmationType == ConfirmationType.none) {
        _moveToNextStep();
      } else {
        _generateAIConfirmation(step, cleanedValue);
      }
    } else {
      setState(() {
        _currentResponse = response;
      });

      if (step.slotName != null) {
        _responses[step.slotName!] = response;
      }

      if (step.confirmationType == ConfirmationType.none) {
        _moveToNextStep();
      } else {
        _generateConfirmation(step, response);
      }
    }
  }

  /// Use AI to extract clean structured data from transcription
  Future<String> _extractDataWithAI(String transcription, ConversationStep step) async {
    String prompt;
    String systemPrompt;

    // Phone numbers can arrive on a step whose slot type was never set to
    // phone, so the wording check decides before the slot type switch.
    if (step.collectsPhoneNumber) {
      return _extractPhoneNumberWithAI(transcription);
    }

    switch (step.slotType) {
      case SlotType.name:
        systemPrompt = 'You extract names from speech transcriptions. Return only the name, nothing else.';
        prompt = '''The user was asked for their name. The transcription is: "$transcription"

Extract the name they provided. If they spelled it out letter by letter (like "J-O-H-N"), convert it to the actual name ("John"). If they said a name normally, return it with proper capitalization.

Return ONLY the name, nothing else.''';
        break;

      case SlotType.datetime:
        systemPrompt = 'You extract dates and times from speech transcriptions. Return only the date/time, nothing else.';
        prompt = '''The user was asked for a date or time. The transcription is: "$transcription"

Extract and format the date/time they provided. Use a clear, readable format like "January 15, 2024" or "3:30 PM" or "January 15, 2024 at 3:30 PM".

Return ONLY the formatted date/time, nothing else.''';
        break;

      case SlotType.address:
        systemPrompt = 'You extract addresses from speech transcriptions. Return only the address, nothing else.';
        prompt = '''The user was asked for an address. The transcription is: "$transcription"

Extract and format the address they provided. Use standard address formatting with proper capitalization. If they spelled out parts letter by letter, convert to the actual text.

Return ONLY the formatted address, nothing else.''';
        break;

      default:
        // Generic extraction for simple/freeform with explicitSpelling
        systemPrompt = 'You extract information from speech transcriptions. Return only the extracted value, nothing else.';
        prompt = '''The user provided this response: "$transcription"

Extract and clean up the information they provided. If they spelled anything out letter by letter, convert to the actual text. Use proper capitalization.

Return ONLY the cleaned value, nothing else.''';
    }

    try {
      final result = await _openAIService.callChatCompletions(
        systemPrompt: systemPrompt,
        conversationHistory: [],
        userMessage: prompt,
        model: 'gpt-4o-mini',
      );
      return result?.content?.trim() ?? transcription;
    } catch (e) {
      debugPrint('Error extracting data: $e');
      return transcription;
    }
  }

  /// Pull a phone number out of a transcription and format it for the screen.
  ///
  /// Speech-to-text renders spoken digits inconsistently ("five five five",
  /// "555 123 4567", "area code 555..."), so the model reduces it to digits and
  /// [formatPhoneNumberForDisplay] does the presentation.
  Future<String> _extractPhoneNumberWithAI(String transcription) async {
    try {
      final result = await _openAIService.callChatCompletions(
        systemPrompt:
            'You extract phone numbers from speech transcriptions. Return only digits, nothing else.',
        conversationHistory: [],
        userMessage: '''The user was asked for a phone number. The transcription is: "$transcription"

Extract the phone number and return ONLY its digits, with no spaces, dashes, parentheses, or words.
Convert spelled-out numbers to digits ("five five five" becomes "555", "triple eight" becomes "888").
Drop filler words like "my number is", "area code", or "extension".
Keep a leading country code only if the user actually said one.

Examples:
- "my number is five five five, one two three, four five six seven" -> 5551234567
- "area code 555 then 123-4567" -> 5551234567
- "it's 1 800 555 0199" -> 18005550199

Return ONLY the digits, nothing else.''',
        model: 'gpt-4o-mini',
      );

      final extracted = result?.content?.trim() ?? transcription;
      return formatPhoneNumberForDisplay(extracted);
    } catch (e) {
      debugPrint('Error extracting phone number: $e');
      // Fall back to formatting whatever digits the transcription already has.
      return formatPhoneNumberForDisplay(transcription);
    }
  }

  /// Use AI to generate a natural confirmation for structured data
  Future<void> _generateAIConfirmation(ConversationStep step, String value) async {
    setState(() {
      _state = KioskState.confirming;
    });

    String promptContext;
    switch (step.slotType) {
      case SlotType.name:
        promptContext = 'name spelling';
        break;
      case SlotType.datetime:
        promptContext = 'date and time';
        break;
      case SlotType.address:
        promptContext = 'address';
        break;
      case SlotType.phone:
        promptContext = 'phone number';
        break;
      case SlotType.simple:
      case SlotType.freeform:
      case SlotType.none:
        promptContext = step.collectsPhoneNumber ? 'phone number' : 'information';
        break;
    }

    try {
      final result = await _openAIService.callChatCompletions(
        systemPrompt: 'You are a friendly assistant confirming information. Be brief and natural.',
        conversationHistory: [],
        userMessage: '''Generate a brief, natural confirmation asking if this $promptContext is correct: "$value"

Keep it conversational and short.
Return ONLY what to say, nothing else.''',
        model: 'gpt-4o-mini',
      );

      final confirmation = result?.content?.trim() ?? "$value - does that look correct?";

      setState(() {
        _aiConfirmation = confirmation;
      });

      _speakText(confirmation);
    } catch (e) {
      debugPrint('Error generating confirmation: $e');
      final fallback = "$value - does that look correct?";
      setState(() {
        _aiConfirmation = fallback;
      });
      _speakText(fallback);
    }
  }

  void _generateConfirmation(ConversationStep step, String response) {
    setState(() {
      _state = KioskState.confirming;
    });

    // Generate confirmation based on type
    String confirmation;

    switch (step.confirmationType) {
      case ConfirmationType.implicit:
        confirmation = "$response. Is that right?";
        break;
      case ConfirmationType.explicit:
        confirmation = "I have $response. Is that correct?";
        break;
      case ConfirmationType.explicitSpelling:
        confirmation = "$response. Does that spelling look correct?";
        break;
      case ConfirmationType.auto:
        // AI decides based on response complexity
        if (step.slotType == SlotType.freeform && response.split(' ').length > 5) {
          confirmation = "$response. Anything else to add?";
        } else {
          confirmation = "$response. Is that right?";
        }
        break;
      case ConfirmationType.none:
        confirmation = '';
        break;
    }

    setState(() {
      _aiConfirmation = confirmation;
    });

    // Speak the confirmation via TTS
    if (confirmation.isNotEmpty) {
      _speakText(confirmation);
    } else {
      _moveToNextStep();
    }
  }


  void _moveToNextStep() {
    if (_currentStepIndex < (_template?.steps.length ?? 0) - 1) {
      setState(() {
        _currentStepIndex++;
        _state = KioskState.speaking;
        _currentResponse = '';
        _aiConfirmation = '';
      });
      _speakCurrentStep();
    } else {
      _completeConversation();
    }
  }

  void _completeConversation() {
    setState(() {
      _state = KioskState.reviewSpeaking;
    });

    // Speak the review question
    _speakText("Here's a summary of your information. Does everything look correct?");
  }

  void _handleReviewSpeakingComplete() {
    setState(() {
      _state = KioskState.reviewListening;
    });
    _startListening();
  }

  Future<void> _handleReviewResponse(String response) async {
    setState(() {
      _state = KioskState.reviewProcessing;
    });

    try {
      // Build summary of collected data for context
      final summaryText = _responses.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');

      final result = await _openAIService.callChatCompletions(
        systemPrompt: 'You interpret user responses about reviewing their submitted information.',
        conversationHistory: [],
        userMessage: '''The user just reviewed their submitted information:
$summaryText

They responded: "$response"

Determine what they want:
- CONFIRMED (they said yes, looks good, that's correct, all good, etc.)
- EDIT|[field_name]|[new_value] (they want to change a specific field - extract which field and the new value)
- ADD|[field_name]|[value] (they want to add something new)
- UNCLEAR (couldn't understand what they want)

Respond with ONLY one of these formats.''',
        model: 'gpt-4o-mini',
      );

      final resultText = (result?.content ?? 'CONFIRMED').trim();

      if (resultText.startsWith('CONFIRMED')) {
        _finalizeAndComplete();
      } else if (resultText.startsWith('EDIT|') || resultText.startsWith('ADD|')) {
        final parts = resultText.split('|');
        if (parts.length >= 3) {
          final fieldName = parts[1].trim().toLowerCase().replaceAll(' ', '_');
          final newValue = parts[2].trim();

          // Find matching field and update
          String? matchedKey;
          for (final key in _responses.keys) {
            if (key.toLowerCase().contains(fieldName) ||
                fieldName.contains(key.toLowerCase())) {
              matchedKey = key;
              break;
            }
          }

          if (matchedKey != null) {
            setState(() {
              _responses[matchedKey!] = _formatValueForSlot(matchedKey, newValue);
            });
          } else if (resultText.startsWith('ADD|')) {
            // Add new field
            setState(() {
              _responses[fieldName] = _formatValueForSlot(fieldName, newValue);
            });
          }

          // Confirm the change and ask again
          setState(() {
            _state = KioskState.reviewSpeaking;
          });
          _speakText("I've updated that. Anything else to change?");
        } else {
          // Couldn't parse, ask again
          setState(() {
            _state = KioskState.reviewSpeaking;
          });
          _speakText("I didn't catch that. What would you like to change?");
        }
      } else {
        // Unclear, ask again
        setState(() {
          _state = KioskState.reviewSpeaking;
        });
        _speakText("Sorry, I didn't understand. Does everything look correct, or would you like to make changes?");
      }
    } catch (e) {
      debugPrint('Error processing review response: $e');
      _finalizeAndComplete();
    }
  }

  /// Re-applies display formatting when a review edit writes to a slot.
  ///
  /// The review flow updates [_responses] by slot name rather than by step, so
  /// look the step back up to keep a corrected phone number formatted.
  String _formatValueForSlot(String slotName, String value) {
    for (final step in _template?.steps ?? const <ConversationStep>[]) {
      if (step.slotName == slotName) {
        return step.collectsPhoneNumber
            ? formatPhoneNumberForDisplay(value)
            : value;
      }
    }
    // Fields added during review have no step to consult.
    return slotName.toLowerCase().contains('phone')
        ? formatPhoneNumberForDisplay(value)
        : value;
  }

  void _finalizeAndComplete() {
    // Save the report
    final reportProvider = context.read<ConversationReportProvider>();
    reportProvider.startSession(
      templateId: _template!.id,
      templateName: _template!.name,
    );

    for (final entry in _responses.entries) {
      reportProvider.recordResponse(entry.key, entry.value);
    }

    reportProvider.completeSession();

    setState(() {
      _state = KioskState.complete;
    });

    // Speak the closing message
    final closingMessage = _template?.effectiveClosingMessage ?? ConversationTemplate.defaultClosingMessage;
    _speakText(closingMessage);
  }

  void _handleRestart() {
    setState(() {
      _state = KioskState.welcome;
      _currentStepIndex = 0;
      _responses.clear();
      _currentResponse = '';
      _aiConfirmation = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_template == null) {
      return Scaffold(
        backgroundColor: AppColors.dreamCloudBlue,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            // Header with exit button
            _buildHeader(),

            // Main content
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: widget.onExit,
          ),
          const Spacer(),
          if (_state != KioskState.welcome &&
              _state != KioskState.complete &&
              _state != KioskState.reviewSpeaking &&
              _state != KioskState.reviewListening &&
              _state != KioskState.reviewProcessing)
            Text(
              'Step ${_currentStepIndex + 1} of ${_template!.steps.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case KioskState.welcome:
        return _buildWelcomeScreen();
      case KioskState.speaking:
      case KioskState.listening:
      case KioskState.processing:
      case KioskState.confirming:
      case KioskState.listeningConfirm:
        return _buildConversationScreen();
      case KioskState.reviewSpeaking:
      case KioskState.reviewListening:
      case KioskState.reviewProcessing:
        return _buildReviewScreen();
      case KioskState.complete:
        return _buildCompleteScreen();
    }
  }

  Widget _buildWelcomeScreen() {
    final agentProvider = context.read<AgentProvider>();
    final activeAgent = agentProvider.activeAgent;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Robot face
          if (activeAgent != null)
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.lightBlueAccent,
                  width: 5,
                ),
              ),
              child: Center(
                child: FacePreview(
                  faceColor: activeAgent.faceColor,
                  eyeShape: activeAgent.eyeShape,
                  faceImageId: activeAgent.faceImageId,
                  customFaceId: activeAgent.customFaceId,
                  size: 280,
                  showBackground: false,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),

          // Template name
          Text(
            _template!.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),

          // Description or welcome message
          Text(
            _template!.description ?? 'Welcome! Tap Start when you\'re ready.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl * 2),

          // Start button
          SizedBox(
            width: 200,
            height: 60,
            child: ElevatedButton(
              onPressed: _handleStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dreamCloudBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 8,
              ),
              child: const Text(
                'Start',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationScreen() {
    final step = _currentStep;
    if (step == null) return const SizedBox();

    final agentProvider = context.read<AgentProvider>();
    final activeAgent = agentProvider.activeAgent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl * 2),
      child: Column(
        children: [
          const Spacer(flex: 1),

          // Robot face
          if (activeAgent != null)
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.lightBlueAccent,
                  width: 4,
                ),
              ),
              child: Center(
                child: FacePreview(
                  faceColor: activeAgent.faceColor,
                  eyeShape: activeAgent.eyeShape,
                  faceImageId: activeAgent.faceImageId,
                  customFaceId: activeAgent.customFaceId,
                  size: 180,
                  showBackground: false,
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.xl),

          // Prompt text
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              step.prompt,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Response display (compact, right under prompt)
          if (_currentResponse.isNotEmpty)
            Text(
              _currentResponse,
              style: TextStyle(
                color: AppColors.dreamCloudBlue,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

          // Confirmation text (what Millie is saying)
          if (_aiConfirmation.isNotEmpty && _state == KioskState.confirming)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _aiConfirmation,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: AppSpacing.lg),

          // State indicator
          _buildStateIndicator(),

          const Spacer(flex: 2),

          // Demo input (for testing without actual voice)
          if (_state == KioskState.listening || _state == KioskState.listeningConfirm)
            _buildDemoInput(),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildStateIndicator() {
    IconData icon;
    String label;
    Color color;

    switch (_state) {
      case KioskState.speaking:
        icon = Icons.volume_up;
        label = 'Speaking...';
        color = AppColors.dreamCloudBlue;
        break;
      case KioskState.listening:
        icon = Icons.mic;
        label = 'Listening...';
        color = AppColors.success;
        break;
      case KioskState.processing:
        icon = Icons.hourglass_top;
        label = 'Processing...';
        color = AppColors.textLight;
        break;
      case KioskState.confirming:
        icon = Icons.volume_up;
        label = 'Confirming...';
        color = AppColors.primaryOrange;
        break;
      case KioskState.listeningConfirm:
        icon = Icons.mic;
        label = 'Listening...';
        color = AppColors.primaryOrange;
        break;
      default:
        return const SizedBox();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }


  Widget _buildDemoInput() {
    final controller = TextEditingController();

    void handleInput(String value) {
      if (value.isEmpty) return;
      if (_state == KioskState.listeningConfirm) {
        _handleConfirmationResponse(value);
      } else {
        _handleResponseReceived(value);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _state == KioskState.listeningConfirm
                    ? 'Confirm or correct...'
                    : 'Type response...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: handleInput,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: () => handleInput(controller.text),
            icon: const Icon(Icons.send, color: AppColors.dreamCloudBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewScreen() {
    final agentProvider = context.read<AgentProvider>();
    final activeAgent = agentProvider.activeAgent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl * 2,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        children: [
          // Robot face
          if (activeAgent != null)
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.lightBlueAccent,
                  width: 3,
                ),
              ),
              child: Center(
                child: FacePreview(
                  faceColor: activeAgent.faceColor,
                  eyeShape: activeAgent.eyeShape,
                  faceImageId: activeAgent.faceImageId,
                  customFaceId: activeAgent.customFaceId,
                  size: 140,
                  showBackground: false,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),

          // Title
          const Text(
            'Review Your Information',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Summary of responses
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._responses.entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // State indicator
          _buildReviewStateIndicator(),

          const SizedBox(height: AppSpacing.lg),

          // Text input for review (same as demo input)
          if (_state == KioskState.reviewListening)
            _buildReviewInput(),
        ],
      ),
    );
  }

  Widget _buildReviewStateIndicator() {
    IconData icon;
    String label;
    Color color;

    switch (_state) {
      case KioskState.reviewSpeaking:
        icon = Icons.volume_up;
        label = 'Speaking...';
        color = AppColors.dreamCloudBlue;
        break;
      case KioskState.reviewListening:
        icon = Icons.mic;
        label = 'Listening...';
        color = AppColors.success;
        break;
      case KioskState.reviewProcessing:
        icon = Icons.hourglass_top;
        label = 'Processing...';
        color = AppColors.textLight;
        break;
      default:
        return const SizedBox();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReviewInput() {
    final controller = TextEditingController();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Confirm or request changes...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  _handleReviewResponse(value);
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _handleReviewResponse(controller.text);
              }
            },
            icon: const Icon(Icons.send, color: AppColors.dreamCloudBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteScreen() {
    final agentProvider = context.read<AgentProvider>();
    final activeAgent = agentProvider.activeAgent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl * 3,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Robot face
          if (activeAgent != null)
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.lightBlueAccent,
                  width: 5,
                ),
              ),
              child: Center(
                child: FacePreview(
                  faceColor: activeAgent.faceColor,
                  eyeShape: activeAgent.eyeShape,
                  faceImageId: activeAgent.faceImageId,
                  customFaceId: activeAgent.customFaceId,
                  size: 280,
                  showBackground: false,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),

          // Title
          const Text(
            'Thank You!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),

          // Subtitle
          Text(
            _template?.effectiveClosingMessage ?? ConversationTemplate.defaultClosingMessage,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Completion check
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.dreamCloudBlue,
              boxShadow: [
                BoxShadow(
                  color: AppColors.dreamCloudBlue.withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 56,
            ),
          ),
        ],
      ),
    );
  }
}
