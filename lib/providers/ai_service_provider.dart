import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/storage_service.dart';

class AIServiceProvider extends ChangeNotifier {
  final StorageService _storage;

  bool _isLoading = false;
  String? _error;
  String? _openaiApiKey;

  AIServiceProvider(this._storage);

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get openaiApiKey => _openaiApiKey;

  /// Check if OpenAI API key is configured
  bool get hasOpenAIKey => _openaiApiKey != null && _openaiApiKey!.isNotEmpty;

  /// Get service by ID - for compatibility with existing code
  AIService? getServiceById(String id) {
    // Return a simple OpenAI service config
    if (hasOpenAIKey) {
      return AIService(
        id: 'openai_default',
        type: AIServiceType.openai,
        displayName: 'OpenAI',
        apiKey: _openaiApiKey,
        status: AIServiceStatus.active,
        isDreamCloud: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    return null;
  }

  /// Get voices for service - for compatibility with existing code
  List<String> getVoicesForService(String serviceId) {
    return ['Alloy', 'Echo', 'Fable', 'Onyx', 'Nova', 'Shimmer'];
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load API key from secure storage
      _openaiApiKey = await _storage.getApiKey('openai');

      debugPrint('AIServiceProvider init - OpenAI key loaded: $hasOpenAIKey');
    } catch (e) {
      debugPrint('AIService init error: $e');
      _error = 'Failed to load API key';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Save OpenAI API key
  Future<bool> saveOpenAIKey(String apiKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _storage.saveApiKey('openai', apiKey);
      _openaiApiKey = apiKey;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error saving OpenAI key: $e');
      _error = 'Failed to save API key';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear OpenAI API key
  Future<void> clearOpenAIKey() async {
    await _storage.deleteApiKey('openai');
    _openaiApiKey = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
