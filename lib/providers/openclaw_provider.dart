import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../services/openclaw_service.dart';
import '../utils/constants.dart';

/// OpenClaw Provider
/// Manages OpenClaw settings and connection state for conversation mode.
/// Games always bypass OpenClaw regardless of these settings.
class OpenClawProvider extends ChangeNotifier {
  final StorageService _storageService;
  final OpenClawService _service = OpenClawService();

  bool _enabled = false;
  String _url = OpenClawService.defaultUrl;
  String? _token;
  bool _isLoading = false;
  String? _error;

  OpenClawProvider(this._storageService);

  // Getters
  bool get enabled => _enabled;
  String get url => _url;
  bool get hasToken => _token != null && _token!.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get error => _error;
  OpenClawConnectionState get connectionState => _service.connectionState;
  bool get isConnected => _service.isConnected;
  String? get connectionError => _service.lastError;

  /// Initialize provider - load settings from storage
  Future<void> init() async {
    debugPrint('OpenClawProvider: Initializing...');

    // Load enabled state
    final enabledStr = await _storageService.getString(StorageKeys.openClawEnabled);
    _enabled = enabledStr == 'true';

    // Load URL (or use default)
    final savedUrl = await _storageService.getString(StorageKeys.openClawUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _url = savedUrl;
    }

    // Load token from secure storage
    _token = await _storageService.getApiKey(StorageKeys.openClawToken);

    debugPrint('OpenClawProvider: Initialized - enabled=$_enabled, url=$_url, hasToken=$hasToken');
    notifyListeners();

    // Auto-connect if enabled and has token
    if (_enabled && hasToken) {
      await connect();
    }
  }

  /// Set enabled state
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;

    _enabled = value;
    await _storageService.saveString(StorageKeys.openClawEnabled, value.toString());
    notifyListeners();

    if (value && hasToken) {
      // Auto-connect when enabling
      await connect();
    } else if (!value) {
      // Disconnect when disabling
      await disconnect();
    }
  }

  /// Set connection URL
  Future<void> setUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    _url = trimmed;
    await _storageService.saveString(StorageKeys.openClawUrl, trimmed);
    notifyListeners();
  }

  /// Set gateway token (stored securely)
  Future<void> setToken(String value) async {
    final trimmed = value.trim();
    _token = trimmed.isEmpty ? null : trimmed;

    if (trimmed.isNotEmpty) {
      await _storageService.saveApiKey(StorageKeys.openClawToken, trimmed);
    } else {
      await _storageService.deleteApiKey(StorageKeys.openClawToken);
    }
    notifyListeners();
  }

  /// Connect to OpenClaw gateway
  Future<bool> connect() async {
    if (!hasToken) {
      _error = 'No gateway token configured';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _service.connect(_url, _token!);
      if (!success) {
        _error = _service.lastError ?? 'Connection failed';
      }
      return success;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Disconnect from OpenClaw gateway
  Future<void> disconnect() async {
    await _service.disconnect();
    notifyListeners();
  }

  /// Test connection with current settings
  Future<bool> testConnection() async {
    if (!hasToken) {
      _error = 'No gateway token configured';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _service.testConnection(_url, _token!);
      if (!success) {
        _error = _service.lastError ?? 'Connection test failed';
      }
      return success;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Send a message to OpenClaw and get response
  /// Returns the assistant's response text, or null on error
  Future<String?> sendMessage(String message) async {
    if (!_enabled) {
      debugPrint('OpenClaw: Not enabled, cannot send message');
      return null;
    }

    // Auto-connect if disconnected
    if (!isConnected) {
      final connected = await connect();
      if (!connected) {
        return null;
      }
    }

    final response = await _service.sendMessage(message);
    if (response == null) {
      _error = _service.lastError;
      notifyListeners();
    }
    return response;
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get the underlying service for direct access if needed
  OpenClawService get service => _service;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
