import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/storage_service.dart';

/// Represents a tool/function call requested by the AI
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  
  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  
  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final function = json['function'] as Map<String, dynamic>;
    return ToolCall(
      id: json['id'] as String,
      name: function['name'] as String,
      arguments: jsonDecode(function['arguments'] as String) as Map<String, dynamic>,
    );
  }
}

/// Chat completion response with content and token usage
class ChatCompletionResponse {
  final String content;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final List<ToolCall>? toolCalls;
  
  ChatCompletionResponse({
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.toolCalls,
  });
  
  /// Whether the AI wants to call tools
  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}

/// Service to manage OpenAI API calls using locally stored API key
class OpenAIService {
  final StorageService _storage;

  OpenAIService(this._storage);

  /// Get the OpenAI API key from local secure storage
  Future<String?> getApiKey() async {
    try {
      final apiKey = await _storage.getApiKey('openai');
      if (apiKey != null && apiKey.isNotEmpty) {
        return apiKey;
      }
      debugPrint('No OpenAI API key found in local storage');
      return null;
    } catch (e) {
      debugPrint('Error getting OpenAI API key: $e');
      return null;
    }
  }

  /// Test if the API key is valid by making a simple API call
  Future<bool> testApiKey(String apiKey) async {
    try {
      final uri = Uri.parse('https://api.openai.com/v1/models');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error testing API key: $e');
      return false;
    }
  }
  
  /// Call OpenAI Chat Completions API (non-streaming)
  /// Returns response with content and token usage
  /// Supports optional tools (function calling)
  Future<ChatCompletionResponse?> callChatCompletions({
    required String systemPrompt,
    required List<Map<String, dynamic>> conversationHistory,
    required String userMessage,
    required String model,
    List<Map<String, dynamic>>? tools,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot call OpenAI: No API key available');
      return null;
    }
    
    try {
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      
      // Build messages array
      final messages = <Map<String, dynamic>>[];
      
      // Add system message
      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });
      
      // Add conversation history
      messages.addAll(conversationHistory);
      
      // Add current user message
      messages.add({
        'role': 'user',
        'content': userMessage,
      });
      
      final requestBody = <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': false, // Non-streaming as per spec
        'temperature': 0.7,
        'max_tokens': 1000, // Increased for more complete responses
      };
      
      // Add tools if provided
      if (tools != null && tools.isNotEmpty) {
        requestBody['tools'] = tools;
        requestBody['tool_choice'] = 'auto'; // Let AI decide when to use tools
      }
      
      debugPrint('Calling OpenAI Chat Completions API...');
      debugPrint('Model: $model');
      debugPrint('Messages count: ${messages.length}');
      if (tools != null) {
        debugPrint('Tools provided: ${tools.length}');
      }
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('OpenAI API response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['choices']?[0]?['message'];
        final content = message?['content'] as String? ?? '';
        
        // Extract token usage
        final usage = data['usage'];
        final promptTokens = usage?['prompt_tokens'] as int? ?? 0;
        final completionTokens = usage?['completion_tokens'] as int? ?? 0;
        final totalTokens = usage?['total_tokens'] as int? ?? 0;
        
        // Check for tool calls
        List<ToolCall>? toolCalls;
        final rawToolCalls = message?['tool_calls'] as List?;
        if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
          toolCalls = rawToolCalls
              .map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
              .toList();
          debugPrint('OpenAI requested ${toolCalls.length} tool call(s)');
          for (final tc in toolCalls) {
            debugPrint('  - ${tc.name}(${tc.arguments})');
          }
        }
        
        debugPrint('OpenAI response received (${content.length} chars)');
        debugPrint('Token usage: $totalTokens total ($promptTokens prompt + $completionTokens completion)');
        
        return ChatCompletionResponse(
          content: content.trim(),
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
          toolCalls: toolCalls,
        );
      } else {
        final errorData = jsonDecode(response.body);
        debugPrint('OpenAI API error: ${errorData['error']?['message'] ?? response.body}');
      }
      
      return null;
    } catch (e) {
      debugPrint('Error calling OpenAI API: $e');
      return null;
    }
  }
  
  /// Continue conversation after tool execution
  /// Used to send tool results back to the AI and get final response
  Future<ChatCompletionResponse?> continueWithToolResults({
    required String systemPrompt,
    required List<Map<String, dynamic>> conversationHistory,
    required String model,
    List<Map<String, dynamic>>? tools,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot call OpenAI: No API key available');
      return null;
    }
    
    try {
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      
      // Build messages array (history should include tool calls and results)
      final messages = <Map<String, dynamic>>[];
      
      // Add system message
      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });
      
      // Add conversation history (includes tool calls and results)
      messages.addAll(conversationHistory);
      
      final requestBody = <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': false,
        'temperature': 0.7,
        'max_tokens': 1000,
      };
      
      // Add tools if provided (in case AI wants to call more)
      if (tools != null && tools.isNotEmpty) {
        requestBody['tools'] = tools;
        requestBody['tool_choice'] = 'auto';
      }
      
      debugPrint('Continuing conversation with tool results...');
      debugPrint('Messages count: ${messages.length}');
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('OpenAI API response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final message = data['choices']?[0]?['message'];
        final content = message?['content'] as String? ?? '';
        
        // Extract token usage
        final usage = data['usage'];
        final promptTokens = usage?['prompt_tokens'] as int? ?? 0;
        final completionTokens = usage?['completion_tokens'] as int? ?? 0;
        final totalTokens = usage?['total_tokens'] as int? ?? 0;
        
        // Check for more tool calls
        List<ToolCall>? toolCalls;
        final rawToolCalls = message?['tool_calls'] as List?;
        if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
          toolCalls = rawToolCalls
              .map((tc) => ToolCall.fromJson(tc as Map<String, dynamic>))
              .toList();
          debugPrint('OpenAI requested ${toolCalls.length} more tool call(s)');
        }
        
        return ChatCompletionResponse(
          content: content.trim(),
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
          toolCalls: toolCalls,
        );
      } else {
        final errorData = jsonDecode(response.body);
        debugPrint('OpenAI API error: ${errorData['error']?['message'] ?? response.body}');
      }
      
      return null;
    } catch (e) {
      debugPrint('Error calling OpenAI API: $e');
      return null;
    }
  }
  
  /// Call OpenAI TTS API (non-streaming)
  Future<String?> textToSpeech({
    required String text,
    required String voice,
    required String model,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot call OpenAI TTS: No API key available');
      return null;
    }
    
    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/speech');
      
      final requestBody = {
        'model': model,
        'input': text,
        'voice': voice.toLowerCase(),
        'response_format': 'mp3',
      };
      
      debugPrint('Calling OpenAI TTS API...');
      debugPrint('Voice: $voice');
      debugPrint('Text length: ${text.length} chars');
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('OpenAI TTS response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Save audio file
        final audioPath = await _saveAudioFile(response.bodyBytes);
        debugPrint('OpenAI TTS audio saved to: $audioPath');
        return audioPath;
      } else {
        final errorData = jsonDecode(response.body);
        debugPrint('OpenAI TTS error: ${errorData['error']?['message'] ?? response.body}');
      }
      
      return null;
    } catch (e) {
      debugPrint('Error calling OpenAI TTS: $e');
      return null;
    }
  }
  
  /// Call OpenAI Whisper API for Speech-to-Text
  /// Call OpenAI Whisper API for Speech-to-Text
  /// If [language] is null, Whisper auto-detects the language (for multilingual use)
  /// If [language] is specified (e.g., 'en'), Whisper transcribes to that language
  Future<String?> speechToText(String audioFilePath, {String? language = 'en'}) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot call OpenAI Whisper: No API key available');
      return null;
    }
    
    try {
      final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
      
      // Read audio file
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        debugPrint('Audio file not found: $audioFilePath');
        return null;
      }
      
      final audioBytes = await audioFile.readAsBytes();
      debugPrint('Calling OpenAI Whisper API...');
      debugPrint('Audio file size: ${audioBytes.length} bytes');
      
      // Validate file size before upload
      if (audioBytes.isEmpty) {
        debugPrint('ERROR: Audio file is empty');
        return null;
      }
      
      if (audioBytes.length > 25 * 1024 * 1024) { // 25MB Whisper limit
        debugPrint('ERROR: Audio file too large (${(audioBytes.length / 1024 / 1024).toStringAsFixed(1)}MB > 25MB limit)');
        return null;
      }
      
      // Retry logic for connection errors (connection reset, connection closed, etc.)
      http.Response? response;
      int retryCount = 0;
      const maxRetries = 2;
      
      while (retryCount <= maxRetries && response == null) {
        // Create a new HTTP client for each attempt to ensure clean connection
        final client = http.Client();
        try {
          debugPrint('Sending request to OpenAI Whisper API...${retryCount > 0 ? " (retry $retryCount)" : ""}');
          
          // Create fresh request for each attempt (can't reuse MultipartRequest)
          final request = http.MultipartRequest('POST', uri);
          request.headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'User-Agent': 'MillieMini/1.0',
          });
          
          // Add audio file - field name must be "file" for Whisper API
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',  // Whisper API requires field name "file"
              audioBytes,
              filename: 'audio.wav',
              contentType: http.MediaType('audio', 'wav'),
            ),
          );
          
          // Add model and language parameters as form fields
          request.fields['model'] = 'whisper-1';
          if (language != null) {
            request.fields['language'] = language;
          }
          request.fields['response_format'] = 'text';
          
          if (retryCount == 0) {
            debugPrint('Sending Whisper API request with ${audioBytes.length} bytes, ${request.fields.length} fields, ${request.files.length} files');
          }
          
          // Exponential backoff for retries (500ms, 1s)
          if (retryCount > 0) {
            await Future.delayed(Duration(milliseconds: retryCount * 500));
          }
          
          // Send request with timeout and use dedicated client
          final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw TimeoutException('Whisper API request timed out after 60 seconds');
            },
          );
          
          debugPrint('Request sent successfully, statusCode: ${streamedResponse.statusCode}');
          
          // Read response with timeout
          response = await http.Response.fromStream(streamedResponse).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException('Whisper API response read timed out after 30 seconds');
            },
          );
          
          debugPrint('OpenAI Whisper response received, status: ${response.statusCode}, body length: ${response.body.length}');
          
          // If successful, break out of retry loop
          if (response.statusCode == 200) {
            break;
          }
          
          // Retry on connection/server errors
          if (response.statusCode >= 500 && response.statusCode < 600) {
            debugPrint('OpenAI Whisper server error ${response.statusCode} - will retry');
            response = null; // Reset to trigger retry
            retryCount++;
            continue;
          }
          
          // For non-retryable errors, break and handle below
          break;
          
        } catch (e, stackTrace) {
          final errorStr = e.toString();
          final isConnectionError = errorStr.contains('Connection reset') || 
                                   errorStr.contains('Connection closed') || 
                                   errorStr.contains('SocketException') ||
                                   errorStr.contains('closed');
          
          if (isConnectionError && retryCount < maxRetries) {
            retryCount++;
            debugPrint('Connection error on attempt ${retryCount - 1}: $e');
            debugPrint('Retrying... (attempt $retryCount/$maxRetries)');
            response = null; // Reset to trigger retry
            continue;
          } else {
            // Not a retryable error, or max retries reached
            debugPrint('Error sending Whisper API request: $e');
            debugPrint('Stack trace: $stackTrace');
            debugPrint('Request details: URI=$uri, file size: ${audioBytes.length} bytes');
            if (isConnectionError) {
              debugPrint('Network connection issue detected after ${retryCount + 1} attempts - this may be a temporary network problem or firewall/proxy issue');
            }
            // Don't rethrow, return null to allow graceful failure
            return null;
          }
        } finally {
          // Always close the client
          client.close();
        }
      }
      
      if (response == null) {
        debugPrint('Failed to get response after ${maxRetries + 1} attempts');
        return null;
      }
      
      debugPrint('OpenAI Whisper response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final transcription = response.body.trim();
        if (transcription.isNotEmpty) {
          debugPrint('Transcription received: $transcription');
          return transcription;
        }
      } else {
        debugPrint('OpenAI Whisper error (${response.statusCode}): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
      }
      
      return null;
    } catch (e) {
      debugPrint('Error calling OpenAI Whisper: $e');
      return null;
    }
  }

  /// Detect which language the text is in from a list of options
  Future<String> detectLanguage(String text, List<String> options) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      return options.first; // Default to first option
    }

    try {
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a language detector. Given text, respond with ONLY the language name from this list: ${options.join(", ")}. No explanation, just the language name.',
            },
            {
              'role': 'user',
              'content': text,
            },
          ],
          'max_tokens': 20,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final detected = data['choices'][0]['message']['content'].toString().trim();
        // Find matching option (case-insensitive)
        for (final option in options) {
          if (detected.toLowerCase().contains(option.toLowerCase())) {
            return option;
          }
        }
      }
    } catch (e) {
      debugPrint('Error detecting language: $e');
    }

    return options.first;
  }

  /// Translate text to target language
  Future<String?> translateText({
    required String text,
    required String targetLanguage,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot translate: No API key available');
      return null;
    }

    try {
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a translator. Translate the user\'s text to $targetLanguage. Respond with ONLY the translation, no explanations or quotes.',
            },
            {
              'role': 'user',
              'content': text,
            },
          ],
          'max_tokens': 500,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        debugPrint('Translation error: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error translating: $e');
    }

    return null;
  }

  /// Generate TTS audio and play it directly
  Future<void> generateAndPlayTTS(String text, String voice) async {
    final audioPath = await textToSpeech(
      text: text,
      voice: voice,
      model: 'tts-1',
    );

    if (audioPath != null) {
      // Use audioplayers to play the file
      final file = File(audioPath);
      if (await file.exists()) {
        // Import and use audioplayers or let the caller handle playback
        debugPrint('TTS audio generated at: $audioPath');
        // The caller should handle playback since this service doesn't have AudioPlayer
      }
    }
  }

  Future<String> _saveAudioFile(List<int> audioBytes) async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/millie_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File(filePath);
      await file.writeAsBytes(audioBytes);
      debugPrint('Saved ${audioBytes.length} bytes to: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error saving audio file: $e');
      rethrow;
    }
  }
  
  /// Analyze a reference image using GPT-4 Vision and create an enhanced prompt
  Future<String?> _analyzeImageForGeneration(File imageFile, String userPrompt) async {
    final apiKey = await getApiKey();
    if (apiKey == null) return null;
    
    try {
      // Read and encode the image
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      // Determine mime type
      final extension = imageFile.path.split('.').last.toLowerCase();
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
      
      final requestBody = {
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'system',
            'content': '''You are an expert at creating DALL-E 3 prompts for ARTISTIC image generation.

CRITICAL RULES:
1. NEVER describe real people, faces, or identifying features
2. If the image contains a person, describe them as a "stylized character", "illustrated figure", or "artistic portrait" 
3. Focus on: colors, lighting, composition, artistic style, mood, background elements
4. Transform any person into an artistic/illustrated version (cartoon, painting, digital art, etc.)
5. Always frame the output as creating ORIGINAL ARTWORK inspired by the reference

The user wants to create NEW ARTWORK. Do not attempt to recreate or describe real people.

Output ONLY the image generation prompt, nothing else.'''
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Reference image provided. User wants: "$userPrompt". Create a DALL-E 3 prompt for ORIGINAL ARTWORK inspired by this reference. Remember: describe as stylized art, not real people.'
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,$base64Image',
                  'detail': 'low'
                }
              }
            ]
          }
        ],
        'max_tokens': 400,
      };
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final enhancedPrompt = data['choices']?[0]?['message']?['content'] as String?;
        
        if (enhancedPrompt != null && enhancedPrompt.isNotEmpty) {
          debugPrint('Image analysis complete, enhanced prompt created');
          return enhancedPrompt.trim();
        }
      } else {
        debugPrint('GPT-4V image analysis failed: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error analyzing reference image: $e');
    }
    
    // Fallback to original prompt if analysis fails
    return null;
  }
  
  /// Generate image using DALL-E API
  /// If referenceImage is provided, uses GPT-4 Vision to analyze it and enhance the prompt
  /// If previousPrompt is provided, includes it for style continuity
  Future<String?> generateImage({
    required String prompt,
    File? referenceImage,
    String? previousPrompt,
    String model = 'dall-e-3',
    String size = '1024x1024',
    String quality = 'standard',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot call DALL-E: No API key available');
      return null;
    }
    
    // Build the prompt with context
    String enhancedPrompt = prompt;
    
    // If reference image provided, use GPT-4V to create an enhanced prompt
    if (referenceImage != null) {
      debugPrint('Reference image provided, analyzing with GPT-4 Vision...');
      final imageDescription = await _analyzeImageForGeneration(referenceImage, prompt);
      if (imageDescription != null) {
        enhancedPrompt = imageDescription;
        debugPrint('Enhanced prompt created from image analysis');
      }
    } else if (previousPrompt != null && previousPrompt.isNotEmpty) {
      // No reference image but has previous context - include for continuity
      enhancedPrompt = 'Continuing from previous image style: $previousPrompt. Now: $prompt';
      debugPrint('Including previous prompt for style continuity');
    }
    
    try {
      final uri = Uri.parse('https://api.openai.com/v1/images/generations');
      
      final requestBody = {
        'model': model,
        'prompt': enhancedPrompt,
        'n': 1,
        'size': size,
        'quality': quality,
      };
      
      debugPrint('Calling DALL-E API...');
      debugPrint('Prompt: ${enhancedPrompt.substring(0, enhancedPrompt.length > 50 ? 50 : enhancedPrompt.length)}...');
      
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 60));
      
      debugPrint('DALL-E response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final imageUrl = data['data']?[0]?['url'] as String?;
        
        if (imageUrl != null && imageUrl.isNotEmpty) {
          debugPrint('DALL-E image generated successfully');
          return imageUrl;
        }
      } else {
        final errorData = jsonDecode(response.body);
        debugPrint('DALL-E error: ${errorData['error']?['message'] ?? response.body}');
      }
      
      return null;
    } catch (e) {
      debugPrint('Error calling DALL-E API: $e');
      return null;
    }
  }
  
  /// Edit image using DALL-E API (requires base image)
  Future<String?> editImage({
    required Uint8List imageBytes,
    required String prompt,
    String size = '1024x1024',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      debugPrint('Cannot call DALL-E edit: No API key available');
      return null;
    }
    
    try {
      final uri = Uri.parse('https://api.openai.com/v1/images/edits');
      
      debugPrint('Calling DALL-E edit API...');
      
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
      });
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'image.png',
        ),
      );
      
      request.fields['prompt'] = prompt;
      request.fields['model'] = 'dall-e-2'; // Only DALL-E 2 supports editing
      request.fields['size'] = size;
      request.fields['n'] = '1';
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('DALL-E edit response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final imageUrl = data['data']?[0]?['url'] as String?;
        
        if (imageUrl != null && imageUrl.isNotEmpty) {
          debugPrint('DALL-E image edited successfully');
          return imageUrl;
        }
      } else {
        final errorData = jsonDecode(response.body);
        debugPrint('DALL-E edit error: ${errorData['error']?['message'] ?? response.body}');
      }
      
      return null;
    } catch (e) {
      debugPrint('Error calling DALL-E edit API: $e');
      return null;
    }
  }
}

