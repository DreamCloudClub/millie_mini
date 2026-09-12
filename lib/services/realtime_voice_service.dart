import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'audio/assistant_audio_buffer.dart';
import 'audio/continuous_pcm_player.dart';
import 'audio/interruption_controller.dart';
import 'note_tools_handler.dart';
import 'openai_service.dart' show ToolCall;

/// Voice states for UI feedback
enum RealtimeVoiceState {
  idle,
  connecting,
  listening,
  processing,
  speaking,
}

/// OpenAI Realtime API voice service
/// Bidirectional streaming: MIC <-> WebSocket <-> OpenAI Realtime API
class RealtimeVoiceService {
  // API key (set from storage service)
  String? _apiKey;

  /// Set the API key to use
  void setApiKey(String key) {
    _apiKey = key;
    final prefix = key.length > 15 ? '${key.substring(0, 7)}...${key.substring(key.length - 4)}' : '***';
    debugPrint('🔑 [RealtimeVoice] API key set: $prefix');
  }

  // WebSocket connection
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;

  // Audio input (microphone)
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  // Audio output
  final AssistantAudioBuffer _audioBuffer = AssistantAudioBuffer();
  final ContinuousPcmPlayer _player = ContinuousPcmPlayer();
  final InterruptionController _interruptionController = InterruptionController();

  // State
  RealtimeVoiceState _state = RealtimeVoiceState.idle;
  bool _isConnected = false;
  bool _isPaused = false;
  bool _shouldEndConversation = false;
  bool _stopped = true;
  String _currentResponseId = '';
  String _currentItemId = '';
  int _responseCount = 0;

  // Idle timeout
  int _idleTimeoutSeconds = 60;
  Timer? _idleTimer;
  DateTime? _lastUserSpeechTime;

  // Session config
  String _systemPrompt = '';
  String _voice = 'alloy';
  Completer<void>? _sessionUpdateCompleter;

  // Tool handler
  NoteToolsHandler? noteToolsHandler;

  // Callbacks
  void Function(RealtimeVoiceState state)? onStateChange;
  void Function(String text)? onTranscription;
  void Function(String text)? onResponse;
  void Function(String error)? onError;
  void Function(bool speaking)? onSpeaking;
  void Function()? onConversationComplete;
  void Function()? onPauseRequested;

  RealtimeVoiceService() {
    _setupCallbacks();
  }

  bool get isConnected => _isConnected;
  bool get isPaused => _isPaused;
  RealtimeVoiceState get state => _state;

  /// Set the idle timeout (in seconds) before conversation pauses
  void setIdleTimeout(int seconds) {
    _idleTimeoutSeconds = seconds;
    debugPrint('⏱️ [Realtime] Idle timeout set to ${seconds}s');
  }

  void _setupCallbacks() {
    _interruptionController.onStateChange = (state) {
      debugPrint('🎙️ [Realtime] Interruption state: ${state.name}');
    };

    _interruptionController.onInterruptionConfirmed = () {
      debugPrint('🛑 [Realtime] Barge-in CONFIRMED - clearing audio');
      _handleConfirmedInterruption();
    };

    _audioBuffer.onReadyToPlay = () {
      debugPrint('🔊 [Realtime] Buffer ready - starting playback');
      _startPlaybackIfReady();
    };

    _audioBuffer.onUnderrun = () {
      debugPrint('⚠️ [Realtime] Buffer underrun');
    };

    _player.onStateChange = (state) {
      debugPrint('🔊 [Realtime] Player state: ${state.name}');
      if (state == PlaybackState.playing) {
        _interruptionController.markAssistantSpeaking();
      }
    };

    _player.onPlaybackComplete = () {
      debugPrint('🔊 [Realtime] Playback complete');
      _handlePlaybackComplete();
    };

    _player.onError = (error) {
      debugPrint('❌ [Realtime] Player error: $error');
      onError?.call('Audio playback error: $error');
    };
  }

  void injectPrompt(String prompt) {
    if (!_isConnected || _isPaused || _stopped) {
      debugPrint('⚠️ [Realtime] Cannot inject prompt - not active');
      return;
    }

    debugPrint('💬 [Realtime] Injecting prompt: $prompt');

    final createItem = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': '[EVENT: $prompt]'},
        ],
      },
    };
    _sendEvent(createItem);
    _sendEvent({'type': 'response.create'});
  }

  Future<void> startConversation({
    required String systemPrompt,
    String voice = 'alloy',
    String? greeting,
  }) async {
    _systemPrompt = systemPrompt;
    _voice = voice;
    _isPaused = false;
    _shouldEndConversation = false;
    _stopped = false;
    _responseCount = 0;
    _audioChunkCount = 0;

    debugPrint('🎤 [Realtime] Starting conversation with voice: $voice');
    _setState(RealtimeVoiceState.connecting);

    try {
      await _player.initialize();

      debugPrint('🔌 [Realtime] Connecting to WebSocket...');
      await _connect();
      debugPrint('🔌 [Realtime] Connected, configuring session...');

      await _configureSession();
      debugPrint('🔌 [Realtime] Session configured');

      // If greeting provided, add it to conversation history
      if (greeting != null && greeting.isNotEmpty) {
        await _sendGreeting(greeting);
      }

      // Start mic stream
      debugPrint('🎙️ [Realtime] Starting audio stream...');
      await _startAudioStream();
      debugPrint('🎙️ [Realtime] Audio stream started');

      _startIdleTimer();

      _interruptionController.markListening();
      _setState(RealtimeVoiceState.listening);
    } catch (e, stackTrace) {
      debugPrint('❌ [Realtime] Connection error: $e');
      debugPrint('❌ [Realtime] Stack trace: $stackTrace');
      onError?.call('Failed to connect to Realtime API: $e');
      _setState(RealtimeVoiceState.idle);
    }
  }

  Future<void> _connect() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    await _disconnect();

    final uri = Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17');

    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'OpenAI-Beta': 'realtime=v1',
      },
    );

    await _channel!.ready;
    _isConnected = true;
    debugPrint('✅ [Realtime] WebSocket connected');

    _channelSubscription = _channel!.stream.listen(
      _handleMessage,
      onError: (error) {
        debugPrint('❌ [Realtime] WebSocket error: $error');
        onError?.call('Connection error');
        _handleDisconnect();
      },
      onDone: () {
        debugPrint('👋 [Realtime] WebSocket closed');
        _handleDisconnect();
      },
    );
  }

  Future<void> _configureSession() async {
    final tools = <Map<String, dynamic>>[];

    // Add note tools if handler is configured
    if (noteToolsHandler != null) {
      for (final tool in NoteToolsHandler.toolDefinitions) {
        tools.add(_convertToolForRealtime(tool));
      }
    }

    final vadConfig = InterruptionController.getRecommendedVadConfig();

    final sessionConfig = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': _systemPrompt,
        'voice': _voice,
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1',
        },
        'turn_detection': vadConfig,
        if (tools.isNotEmpty) 'tools': tools,
      },
    };

    debugPrint('📝 [Realtime] Sending session config with voice: $_voice');

    _sessionUpdateCompleter = Completer<void>();
    _sendEvent(sessionConfig);

    try {
      await _sessionUpdateCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ [Realtime] Session update timeout');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [Realtime] Session update wait error: $e');
    }
    _sessionUpdateCompleter = null;

    debugPrint('📝 [Realtime] Session configured with ${tools.length} tools');
  }

  Map<String, dynamic> _convertToolForRealtime(Map<String, dynamic> chatTool) {
    final function = chatTool['function'] as Map<String, dynamic>;
    return {
      'type': 'function',
      'name': function['name'],
      'description': function['description'],
      'parameters': function['parameters'],
    };
  }

  Future<void> _sendGreeting(String greeting) async {
    final createItem = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': greeting},
        ],
      },
    };
    _sendEvent(createItem);

    debugPrint('🗣️ [Realtime] Greeting added to history: $greeting');
    onResponse?.call(greeting);
  }

  Future<void> _startAudioStream() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    _audioStreamSubscription = stream.listen(
      (data) {
        if (!_isConnected || _isPaused) return;
        // Don't send audio while assistant is speaking
        if (_player.isPlaying) return;
        _sendAudioChunk(data);
      },
      onError: (error) {
        debugPrint('❌ [Realtime] Audio stream error: $error');
      },
    );

    debugPrint('🎤 [Realtime] Audio stream started (24kHz PCM16)');
  }

  int _audioChunkCount = 0;

  void _sendAudioChunk(Uint8List audioData) {
    _audioChunkCount++;
    if (_audioChunkCount % 25 == 1) {
      debugPrint('🎵 [Realtime] Audio chunk #$_audioChunkCount (${audioData.length} bytes)');
    }
    final event = {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(audioData),
    };
    _sendEvent(event);
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      if (type != 'response.audio.delta' && type != 'response.audio_transcript.delta') {
        debugPrint('📥 [Realtime] Received: $type');
      }

      switch (type) {
        case 'session.created':
          debugPrint('✅ [Realtime] Session created');
          break;

        case 'session.updated':
          if (_sessionUpdateCompleter != null && !_sessionUpdateCompleter!.isCompleted) {
            _sessionUpdateCompleter!.complete();
          }
          break;

        case 'input_audio_buffer.speech_started':
          debugPrint('🎤 [Realtime] User speech started');
          _handleUserSpeechStarted();
          break;

        case 'input_audio_buffer.speech_stopped':
          debugPrint('🎤 [Realtime] User speech stopped');
          _handleUserSpeechStopped();
          break;

        case 'conversation.item.input_audio_transcription.completed':
          final transcript = message['transcript'] as String? ?? '';
          debugPrint('👤 [Realtime] User: $transcript');
          if (transcript.isNotEmpty) {
            onTranscription?.call(transcript);
            _checkForPauseCommand(transcript);
          }
          break;

        case 'response.created':
          _responseCount++;
          final responseId = message['response']?['id'] as String? ?? '';
          _currentResponseId = responseId;
          debugPrint('🤖 [Realtime] Response #$_responseCount started: $_currentResponseId');
          _audioBuffer.markResponseStart(responseId);
          _interruptionController.markAssistantBuffering();
          break;

        case 'response.output_item.added':
          final item = message['item'] as Map<String, dynamic>?;
          _currentItemId = item?['id'] as String? ?? '';
          break;

        case 'response.audio.delta':
          final delta = message['delta'] as String? ?? '';
          if (delta.isNotEmpty) {
            _handleAudioDelta(delta);
          }
          break;

        case 'response.audio.done':
          debugPrint('🔊 [Realtime] Audio response complete');
          _audioBuffer.markResponseEnd(_currentResponseId);
          break;

        case 'response.audio_transcript.done':
          final transcript = message['transcript'] as String? ?? '';
          debugPrint('🤖 [Realtime] AI: $transcript');
          if (transcript.isNotEmpty) {
            onResponse?.call(transcript);
          }
          break;

        case 'response.function_call_arguments.done':
          _handleFunctionCall(message);
          break;

        case 'response.done':
          debugPrint('✅ [Realtime] Response complete');
          _handleResponseComplete();
          break;

        case 'error':
          final error = message['error'] as Map<String, dynamic>?;
          final errorMsg = error?['message'] as String? ?? 'Unknown error';
          debugPrint('❌ [Realtime] Error: $errorMsg');
          onError?.call(errorMsg);
          break;
      }
    } catch (e) {
      debugPrint('⚠️ [Realtime] Error parsing message: $e');
    }
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _lastUserSpeechTime = DateTime.now();
    _idleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkIdleTimeout();
    });
  }

  void _checkIdleTimeout() {
    if (_lastUserSpeechTime == null || !_isConnected || _isPaused || _stopped) {
      return;
    }
    final secondsSinceLastSpeech = DateTime.now().difference(_lastUserSpeechTime!).inSeconds;
    if (secondsSinceLastSpeech >= _idleTimeoutSeconds) {
      debugPrint('⏱️ [Realtime] Idle timeout - pausing');
      _idleTimer?.cancel();
      pause();
      onPauseRequested?.call();
    }
  }

  void _resetIdleTimer() {
    _lastUserSpeechTime = DateTime.now();
  }

  void _handleUserSpeechStarted() {
    if (_player.isPlaying) {
      debugPrint('🎤 [Realtime] Ignoring speech_started while playing');
      return;
    }
    _resetIdleTimer();
    _setState(RealtimeVoiceState.listening);
    _interruptionController.handleSpeechStarted();
  }

  void _handleUserSpeechStopped() {
    _interruptionController.handleSpeechStopped();
    _setState(RealtimeVoiceState.processing);
  }

  void _handleConfirmedInterruption() {
    _audioBuffer.clear(reason: 'user_interruption');
    _player.handleInterruption();
    onSpeaking?.call(false);

    if (_currentResponseId.isNotEmpty) {
      _sendEvent({'type': 'response.cancel'});
    }

    _setState(RealtimeVoiceState.listening);
  }

  void _handleAudioDelta(String base64Audio) {
    if (_stopped || _isPaused) return;
    if (_interruptionController.isInterruptionConfirmed) return;

    try {
      final audioBytes = base64Decode(base64Audio);
      _audioBuffer.appendChunk(audioBytes, responseId: _currentResponseId);
    } catch (e) {
      debugPrint('⚠️ [Realtime] Audio decode error: $e');
    }
  }

  void _startPlaybackIfReady() {
    if (_stopped || _isPaused) return;
    if (_player.isPlaying || _player.state == PlaybackState.starting) return;

    _setState(RealtimeVoiceState.speaking);
    onSpeaking?.call(true);
    _player.start(_audioBuffer);
  }

  void _handlePlaybackComplete() {
    onSpeaking?.call(false);
    _interruptionController.markAssistantDone();

    if (!_isPaused && !_stopped) {
      _restartAudioStream().then((_) {
        _setState(RealtimeVoiceState.listening);
        debugPrint('🎤 [Realtime] Ready for next input');
      });
    }
  }

  Future<void> _restartAudioStream() async {
    debugPrint('🎙️ [Realtime] Restarting audio stream...');
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    try {
      await _recorder.stop();
    } catch (e) {
      // May already be stopped
    }

    _audioChunkCount = 0;
    await _startAudioStream();
  }

  Future<void> _handleFunctionCall(Map<String, dynamic> message) async {
    final callId = message['call_id'] as String? ?? '';
    final name = message['name'] as String? ?? '';
    final argumentsStr = message['arguments'] as String? ?? '{}';

    debugPrint('🔧 [Realtime] Function call: $name');

    Map<String, dynamic> arguments;
    try {
      arguments = jsonDecode(argumentsStr) as Map<String, dynamic>;
    } catch (e) {
      arguments = {};
    }

    // Execute tool using note tools handler
    NoteToolResult result;
    if (noteToolsHandler != null) {
      final toolCall = ToolCall(
        id: callId,
        name: name,
        arguments: arguments,
      );
      result = await noteToolsHandler!.executeTool(toolCall);
    } else {
      result = NoteToolResult(success: false, message: 'No handler for: $name');
    }

    debugPrint('🔧 [Realtime] Tool $name: ${result.success ? "success" : "failed"}');
    _sendFunctionResult(callId, result);
  }

  void _sendFunctionResult(String callId, NoteToolResult result) {
    final outputEvent = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': jsonEncode(result.toJson()),
      },
    };
    _sendEvent(outputEvent);
    _sendEvent({'type': 'response.create'});
  }

  void _handleResponseComplete() {
    _currentResponseId = '';
    _currentItemId = '';

    if (_shouldEndConversation) {
      debugPrint('🏁 [Realtime] Ending conversation');
      _shouldEndConversation = false;
      onConversationComplete?.call();
      stopConversation();
    }
  }

  void _checkForPauseCommand(String text) {
    final words = text.toLowerCase().replaceAll(RegExp(r'[.,!?]'), '').split(RegExp(r'\s+'));
    if (words.contains('pause')) {
      debugPrint('⏸️ [Realtime] Pause command detected');
      pause();
      onPauseRequested?.call();
    }
  }

  void pause() {
    _isPaused = true;
    _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    _recorder.stop();
    _audioBuffer.clear(reason: 'pause');
    _player.stop();
    onSpeaking?.call(false);
    _interruptionController.markIdle();
    debugPrint('⏸️ [Realtime] Conversation paused');
  }

  Future<void> resume() async {
    _isPaused = false;
    _stopped = false;

    if (!_isConnected) {
      debugPrint('⚠️ [Realtime] Not connected - reconnecting...');
      try {
        await _player.initialize();
        await _connect();
        await _configureSession();
        await _startAudioStream();
        debugPrint('🔄 [Realtime] Reconnected and resumed');
      } catch (e) {
        debugPrint('❌ [Realtime] Failed to reconnect: $e');
        onError?.call('Failed to reconnect: $e');
        return;
      }
    } else {
      await _startAudioStream();
      debugPrint('▶️ [Realtime] Conversation resumed');
    }

    _startIdleTimer();
    _interruptionController.markListening();
    _setState(RealtimeVoiceState.listening);
  }

  Future<void> stopConversation() async {
    debugPrint('🛑 [Realtime] Stopping conversation');

    _idleTimer?.cancel();
    _idleTimer = null;
    _stopped = true;
    _isPaused = false;
    _shouldEndConversation = false;

    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _recorder.stop();

    _audioBuffer.clear(reason: 'stop_conversation');
    await _player.stop();

    await _disconnect();

    _interruptionController.markIdle();
    _setState(RealtimeVoiceState.idle);
    onSpeaking?.call(false);
  }

  Future<void> _disconnect() async {
    _isConnected = false;
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _handleDisconnect() {
    _isConnected = false;
    _interruptionController.markError();
    _setState(RealtimeVoiceState.idle);
    onSpeaking?.call(false);
  }

  void _sendEvent(Map<String, dynamic> event) {
    if (_channel != null && _isConnected) {
      final eventType = event['type'] as String?;
      if (eventType != 'input_audio_buffer.append') {
        debugPrint('📤 [Realtime] Sending: $eventType');
      }
      _channel!.sink.add(jsonEncode(event));
    } else {
      debugPrint('⚠️ [Realtime] Cannot send - not connected');
    }
  }

  void _setState(RealtimeVoiceState newState) {
    _state = newState;
    onStateChange?.call(newState);
    debugPrint('📍 [Realtime] State: ${newState.name}');
  }

  Future<void> dispose() async {
    await stopConversation();
    _recorder.dispose();
    await _player.dispose();
    _interruptionController.dispose();
  }
}
