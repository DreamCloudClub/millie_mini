import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Connection state for OpenClaw WebSocket
enum OpenClawConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// OpenClaw Service
/// Handles WebSocket communication with local OpenClaw gateway.
/// Used for conversation mode only - games bypass this entirely.
class OpenClawService {
  static const String defaultUrl = 'ws://127.0.0.1:18789';
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration messageTimeout = Duration(seconds: 120);

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  OpenClawConnectionState _connectionState = OpenClawConnectionState.disconnected;
  String? _lastError;
  String? _connId;
  String? _sessionKey;
  int _requestId = 0;
  String? _token;

  // Pending chat responses
  String? _currentRunId;
  final StringBuffer _streamingResponse = StringBuffer();
  Completer<String?>? _chatCompleter;

  OpenClawConnectionState get connectionState => _connectionState;
  String? get lastError => _lastError;
  bool get isConnected => _connectionState == OpenClawConnectionState.connected;

  /// Connect to OpenClaw gateway with token authentication
  Future<bool> connect(String url, String token) async {
    if (_connectionState == OpenClawConnectionState.connecting) {
      debugPrint('OpenClaw: Already connecting...');
      return false;
    }

    // Close any existing connection
    await disconnect();

    _connectionState = OpenClawConnectionState.connecting;
    _lastError = null;
    _token = token;

    try {
      debugPrint('OpenClaw: Connecting to $url');

      final uri = Uri.parse(url);
      _channel = IOWebSocketChannel.connect(uri);

      final connectCompleter = Completer<bool>();
      Timer? timeoutTimer;

      timeoutTimer = Timer(connectionTimeout, () {
        if (!connectCompleter.isCompleted) {
          _lastError = 'Connection timeout';
          _connectionState = OpenClawConnectionState.error;
          connectCompleter.complete(false);
        }
      });

      _subscription = _channel!.stream.listen(
        (message) {
          _handleMessage(message, connectCompleter, timeoutTimer);
        },
        onError: (error) {
          debugPrint('OpenClaw: WebSocket error: $error');
          _lastError = error.toString();
          _connectionState = OpenClawConnectionState.error;
          if (!connectCompleter.isCompleted) {
            timeoutTimer?.cancel();
            connectCompleter.complete(false);
          }
          _cleanupPendingChat('Connection error');
        },
        onDone: () {
          debugPrint('OpenClaw: WebSocket closed');
          final wasConnected = _connectionState == OpenClawConnectionState.connected;
          _connectionState = OpenClawConnectionState.disconnected;
          if (!connectCompleter.isCompleted) {
            timeoutTimer?.cancel();
            _lastError = 'Connection closed unexpectedly';
            connectCompleter.complete(false);
          }
          _cleanupPendingChat(wasConnected ? 'Connection closed' : 'Failed to connect');
        },
      );

      return await connectCompleter.future;
    } catch (e) {
      debugPrint('OpenClaw: Connection error: $e');
      _lastError = e.toString();
      _connectionState = OpenClawConnectionState.error;
      return false;
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message, Completer<bool>? connectCompleter, Timer? timeoutTimer) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final event = data['event'] as String?;

      if (type == 'event' && event == 'connect.challenge') {
        _sendConnectRequest();
      } else if (type == 'res') {
        _handleResponse(data, connectCompleter, timeoutTimer);
      } else if (type == 'event' && event == 'agent') {
        _handleAgentEvent(data);
      } else if (type == 'event' && event == 'chat') {
        _handleChatEvent(data);
      }
    } catch (e) {
      debugPrint('OpenClaw: Failed to parse message: $e');
    }
  }

  /// Handle response messages
  void _handleResponse(Map<String, dynamic> data, Completer<bool>? connectCompleter, Timer? timeoutTimer) {
    final id = data['id'] as String?;
    final ok = data['ok'] as bool? ?? false;

    // Handle connect response
    if (id != null && id.startsWith('connect-')) {
      timeoutTimer?.cancel();
      if (ok) {
        final payload = data['payload'] as Map<String, dynamic>?;
        _connId = payload?['server']?['connId'] as String?;
        _sessionKey = payload?['snapshot']?['sessionDefaults']?['mainSessionKey'] as String? ?? 'agent:main:main';
        _connectionState = OpenClawConnectionState.connected;
        debugPrint('OpenClaw: Connected (connId: $_connId, sessionKey: $_sessionKey)');
        if (connectCompleter != null && !connectCompleter.isCompleted) {
          connectCompleter.complete(true);
        }
      } else {
        final error = data['error'] as Map<String, dynamic>?;
        _lastError = error?['message'] as String? ?? 'Connection failed';
        _connectionState = OpenClawConnectionState.error;
        debugPrint('OpenClaw: Connect failed: $_lastError');
        if (connectCompleter != null && !connectCompleter.isCompleted) {
          connectCompleter.complete(false);
        }
      }
      return;
    }

    // Handle chat.send response
    if (id != null && id.startsWith('chat-')) {
      if (!ok) {
        final error = data['error'] as Map<String, dynamic>?;
        _lastError = error?['message'] as String? ?? 'Chat failed';
        debugPrint('OpenClaw: Chat error: $_lastError');
        _completeChatWithError(_lastError!);
      }
      // If ok, wait for streaming events
    }
  }

  /// Handle agent streaming events
  void _handleAgentEvent(Map<String, dynamic> data) {
    final payload = data['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    final runId = payload['runId'] as String?;
    final stream = payload['stream'] as String?;
    final eventData = payload['data'] as Map<String, dynamic>?;

    // Only process events for our current request
    if (runId != _currentRunId) return;

    if (stream == 'assistant' && eventData != null) {
      // This contains the full text so far (not just delta)
      final text = eventData['text'] as String?;
      if (text != null) {
        _streamingResponse.clear();
        _streamingResponse.write(text);
      }
    } else if (stream == 'lifecycle') {
      final phase = eventData?['phase'] as String?;
      if (phase == 'end') {
        // Lifecycle end - complete the chat
        _completeChatWithResponse();
      }
    }
  }

  /// Handle chat events (contains final message)
  void _handleChatEvent(Map<String, dynamic> data) {
    final payload = data['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    final runId = payload['runId'] as String?;
    final state = payload['state'] as String?;

    // Only process events for our current request
    if (runId != _currentRunId) return;

    if (state == 'final') {
      // Extract final message text
      final message = payload['message'] as Map<String, dynamic>?;
      final content = message?['content'] as List<dynamic>?;
      if (content != null && content.isNotEmpty) {
        final firstContent = content[0] as Map<String, dynamic>?;
        if (firstContent?['type'] == 'text') {
          final text = firstContent?['text'] as String?;
          if (text != null) {
            _streamingResponse.clear();
            _streamingResponse.write(text);
          }
        }
      }
      _completeChatWithResponse();
    }
  }

  /// Complete chat with accumulated response
  void _completeChatWithResponse() {
    if (_chatCompleter != null && !_chatCompleter!.isCompleted) {
      final response = _streamingResponse.toString();
      _chatCompleter!.complete(response.isNotEmpty ? response : null);
    }
    _currentRunId = null;
    _streamingResponse.clear();
  }

  /// Complete chat with error
  void _completeChatWithError(String error) {
    if (_chatCompleter != null && !_chatCompleter!.isCompleted) {
      _chatCompleter!.complete(null);
    }
    _currentRunId = null;
    _streamingResponse.clear();
  }

  /// Send connect request after receiving challenge
  void _sendConnectRequest() {
    if (_channel == null || _token == null) return;

    final request = {
      'type': 'req',
      'method': 'connect',
      'id': 'connect-${++_requestId}',
      'params': {
        'minProtocol': 3,
        'maxProtocol': 3,
        'client': {
          'id': 'cli',
          'version': '1.0.0',
          'platform': 'flutter',
          'mode': 'cli',
        },
        'role': 'operator',
        'scopes': ['chat', 'sessions', 'operator.read', 'operator.write'],
        'auth': {
          'token': _token,
        },
      },
    };

    debugPrint('OpenClaw: Sending connect request');
    _channel!.sink.add(jsonEncode(request));
  }

  /// Disconnect from OpenClaw gateway
  Future<void> disconnect() async {
    _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;

    _connectionState = OpenClawConnectionState.disconnected;
    _connId = null;
    _sessionKey = null;
    _token = null;
    _currentRunId = null;
    _streamingResponse.clear();
    _cleanupPendingChat('Disconnected');
    debugPrint('OpenClaw: Disconnected');
  }

  /// Send a message to OpenClaw and get a response
  /// Returns the assistant's response text, or null on error
  Future<String?> sendMessage(String message) async {
    if (!isConnected || _channel == null) {
      _lastError = 'Not connected';
      return null;
    }

    if (_sessionKey == null) {
      _lastError = 'No session key';
      return null;
    }

    try {
      final chatId = 'chat-${++_requestId}';
      final idempotencyKey = 'idem-${DateTime.now().millisecondsSinceEpoch}';
      _currentRunId = idempotencyKey;
      _streamingResponse.clear();
      _chatCompleter = Completer<String?>();

      final request = {
        'type': 'req',
        'method': 'chat.send',
        'id': chatId,
        'params': {
          'sessionKey': _sessionKey,
          'idempotencyKey': idempotencyKey,
          'message': message,
        },
      };

      debugPrint('OpenClaw: Sending chat (id=$chatId): ${message.substring(0, message.length > 50 ? 50 : message.length)}...');
      _channel!.sink.add(jsonEncode(request));

      // Wait for streaming response to complete
      final response = await _chatCompleter!.future.timeout(
        messageTimeout,
        onTimeout: () {
          _currentRunId = null;
          _streamingResponse.clear();
          _lastError = 'Response timeout';
          return null;
        },
      );

      if (response != null) {
        debugPrint('OpenClaw: Response: ${response.substring(0, response.length > 50 ? 50 : response.length)}...');
      }

      return response;
    } catch (e) {
      debugPrint('OpenClaw: Send error: $e');
      _lastError = e.toString();
      return null;
    }
  }

  /// Clean up pending chat
  void _cleanupPendingChat(String reason) {
    if (_chatCompleter != null && !_chatCompleter!.isCompleted) {
      _chatCompleter!.complete(null);
    }
    _chatCompleter = null;
    _currentRunId = null;
    _streamingResponse.clear();
  }

  /// Test connection with current settings
  /// Returns true if connection succeeds, false otherwise
  Future<bool> testConnection(String url, String token) async {
    final connected = await connect(url, token);
    if (connected) {
      await disconnect();
    }
    return connected;
  }

  /// Dispose of resources
  void dispose() {
    disconnect();
  }
}
