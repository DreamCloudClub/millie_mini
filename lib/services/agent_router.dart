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
      case AIServiceType.dreamCloud:
        return 'https://api.dreamcloud.ai/v1'; // Placeholder
      case AIServiceType.openai:
        return 'https://api.openai.com/v1';
      case AIServiceType.gemini:
        return 'https://generativelanguage.googleapis.com/v1beta';
      case AIServiceType.anthropic:
        return 'https://api.anthropic.com/v1';
    }
  }

  /// Get the voice ID for the TTS service
  String getVoiceId(AIServiceType type, String voiceName) {
    // Map voice names to voice IDs based on service
    switch (type) {
      case AIServiceType.dreamCloud:
      case AIServiceType.openai:
        // OpenAI voices are lowercase
        return voiceName.toLowerCase();
      case AIServiceType.gemini:
        // Google TTS voice IDs
        return voiceName;
      case AIServiceType.anthropic:
        // Anthropic doesn't have TTS, use fallback
        return 'default';
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
      case AIServiceType.dreamCloud:
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
        
      case AIServiceType.gemini:
        return {
          'contents': [
            {
              'parts': [
                {'text': '$systemPrompt\n\n${_formatMessages(messages)}\n\nUser: $userMessage'}
              ]
            }
          ],
          'generationConfig': {
            'maxOutputTokens': 500,
            'temperature': 0.7,
          },
        };
        
      case AIServiceType.anthropic:
        return {
          'model': 'claude-3-haiku-20240307',
          'system': systemPrompt,
          'messages': [
            ...messages.map((m) => <String, dynamic>{
              'role': m['role'] == 'assistant' ? 'assistant' : 'user',
              'content': m['content'],
            }),
            {'role': 'user', 'content': userMessage},
          ],
          'max_tokens': 500,
        };
    }
  }

  String _formatMessages(List<Map<String, String>> messages) {
    return messages.map((m) {
      final role = m['role'] == 'assistant' ? 'Assistant' : 'User';
      return '$role: ${m['content']}';
    }).join('\n');
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

