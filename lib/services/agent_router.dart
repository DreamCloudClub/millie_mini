import '../models/models.dart';
import 'storage_service.dart';

/// Routes AI requests to the appropriate service based on the active agent's configuration
class AgentRouter {
  final StorageService _storage;

  AgentRouter(this._storage);

  /// Get the API configuration for a given AI service
  Future<AIServiceConfig?> getServiceConfig(AIService service) async {
    final apiKey = await _storage.getApiKey(service.id);

    return AIServiceConfig(
      type: service.type,
      apiKey: apiKey,
      baseUrl: _getBaseUrl(service.type),
    );
  }

  String _getBaseUrl(AIServiceType type) {
    switch (type) {
      case AIServiceType.openai:
        return 'https://api.openai.com/v1';
    }
  }

  /// Get the voice ID for the TTS service
  String getVoiceId(AIServiceType type, String voiceName) {
    switch (type) {
      case AIServiceType.openai:
        // OpenAI voices are lowercase
        return voiceName.toLowerCase();
    }
  }

  /// Build the LLM request body based on service type
  Map<String, dynamic> buildLLMRequest({
    required AIServiceType type,
    required String systemPrompt,
    required List<Map<String, String>> messages,
    required String userMessage,
  }) {
    switch (type) {
      case AIServiceType.openai:
        return {
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...messages,
            {'role': 'user', 'content': userMessage},
          ],
          'max_tokens': 500,
          'temperature': 0.7,
        };
    }
  }
}

/// Configuration for an AI service
class AIServiceConfig {
  final AIServiceType type;
  final String? apiKey;
  final String baseUrl;

  AIServiceConfig({
    required this.type,
    this.apiKey,
    required this.baseUrl,
  });

  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;
}
