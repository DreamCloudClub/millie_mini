import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

/// Dream Cloud API configuration
class DreamCloudAPI {
  static const String baseUrl = 'https://dreamcloudclub.org';
  static const String subscriptionEndpoint = '/wp-json/dreamcloud/v1/check-subscription';
}

class AIServiceProvider extends ChangeNotifier {
  final StorageService _storage;
  final _uuid = const Uuid();
  
  List<AIService> _services = [];
  bool _isLoading = false;
  String? _error;
  
  AIServiceProvider(this._storage);
  
  List<AIService> get services => _services;
  AIService? get dreamCloudService => 
      _services.firstWhere((s) => s.isDreamCloud, orElse: () => AIService.dreamCloud());
  List<AIService> get customServices => 
      _services.where((s) => !s.isDreamCloud).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _services = await _storage.getAIServices();
      
      // Get logged-in user's email
      final userEmail = SupabaseConfig.currentUser?.email;
      
      // Check if Dream Cloud service exists
      var dcIndex = _services.indexWhere((s) => s.isDreamCloud);
      if (dcIndex == -1) {
        // No Dream Cloud service found, create default
        _services.insert(0, AIService.dreamCloud());
        dcIndex = 0;
      }
      
      // Auto-check subscription status on every app open (if user is logged in)
      // ALWAYS check subscription status first, then fall back to trial if needed
      if (userEmail != null && userEmail.isNotEmpty) {
        // Check subscription status first (this will fall back to trial if no active subscription)
        await updateDreamCloudSubscription(userEmail);
      }
    } catch (e) {
      debugPrint('AIService init error: $e');
      _error = 'Failed to load AI services';
      _services = [AIService.dreamCloud()];
    }
    
    _isLoading = false;
    notifyListeners();
    
    // Listen for auth state changes to auto-refresh subscription
    SupabaseConfig.authStateChanges.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        // User logged in - auto-check subscription status
        final userEmail = data.session?.user.email;
        if (userEmail != null && userEmail.isNotEmpty) {
          updateDreamCloudSubscription(userEmail);
        }
      }
    });
  }
  
  /// Refresh subscription status (call after login or when needed)
  Future<void> refreshSubscriptionStatus() async {
    final userEmail = SupabaseConfig.currentUser?.email;
    if (userEmail != null && userEmail.isNotEmpty) {
      await updateDreamCloudSubscription(userEmail);
    }
  }
  
  AIService? getServiceById(String id) {
    try {
      return _services.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
  
  Future<AIService> addCustomService({
    required AIServiceType type,
    required String displayName,
    required String apiKey,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Validate API key (in production, make a test call)
      if (apiKey.isEmpty) {
        throw Exception('API key is required');
      }
      
      // Simulate API key validation
      await Future.delayed(const Duration(milliseconds: 500));
      
      final now = DateTime.now();
      final service = AIService(
        id: _uuid.v4(),
        type: type,
        displayName: displayName,
        apiKey: apiKey,
        status: AIServiceStatus.active,
        isDreamCloud: false,
        createdAt: now,
        updatedAt: now,
      );
      
      // Save API key securely
      await _storage.saveApiKey(service.id, apiKey);
      
      _services.add(service);
      await _saveServices();
      
      _isLoading = false;
      notifyListeners();
      return service;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> updateService({
    required String serviceId,
    String? displayName,
    String? apiKey,
    AIServiceStatus? status,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final index = _services.indexWhere((s) => s.id == serviceId);
      if (index == -1) {
        throw Exception('Service not found');
      }
      
      final service = _services[index];
      
      // If updating API key, validate it
      if (apiKey != null && apiKey.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _storage.saveApiKey(serviceId, apiKey);
      }
      
      _services[index] = service.copyWith(
        displayName: displayName,
        apiKey: apiKey,
        status: status,
        updatedAt: DateTime.now(),
      );
      
      await _saveServices();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Check if user is within 7-day free trial period (based on Supabase account creation)
  Map<String, dynamic>? _checkTrialStatus() {
    final user = SupabaseConfig.currentUser;
    if (user == null || user.createdAt == null) return null;
    
    final accountCreatedAt = DateTime.parse(user.createdAt);
    final now = DateTime.now();
    final daysSinceSignup = now.difference(accountCreatedAt).inDays;
    
    if (daysSinceSignup <= 7) {
      final daysRemaining = 7 - daysSinceSignup;
      return {
        'status': 'trial',
        'message': 'Free trial active. $daysRemaining day${daysRemaining != 1 ? 's' : ''} remaining.',
        'days_remaining': daysRemaining,
      };
    }
    
    return null;
  }
  
  Future<void> updateDreamCloudSubscription(String email) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final index = _services.indexWhere((s) => s.isDreamCloud);
      if (index == -1) {
        _services.insert(0, AIService.dreamCloud());
      }
      
      AIServiceStatus newStatus;
      String statusMessage;
      
      // Check WordPress subscription first (higher priority)
      if (email.isNotEmpty) {
        try {
          final uri = Uri.parse('${DreamCloudAPI.baseUrl}${DreamCloudAPI.subscriptionEndpoint}');
          debugPrint('Checking subscription at: $uri');
          
          final response = await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'email': email}),
          ).timeout(const Duration(seconds: 10));
          
          debugPrint('Subscription check response: ${response.statusCode}');
          debugPrint('Response body: ${response.body}');
          
          if (response.statusCode == 200 || response.statusCode == 404) {
            final data = jsonDecode(response.body);
            final status = data['status'] as String? ?? 'unknown';
            final message = data['message'] as String? ?? '';
            
            // Map API status to enum
            switch (status) {
              case 'holder':
                newStatus = AIServiceStatus.holder;
                statusMessage = message.isNotEmpty ? message : 'Status: holder';
                break;
              case 'basic':
                newStatus = AIServiceStatus.basic;
                statusMessage = message.isNotEmpty ? message : 'Status: basic';
                break;
              case 'pro':
                newStatus = AIServiceStatus.pro;
                statusMessage = message.isNotEmpty ? message : 'Status: pro';
                break;
              case 'active':
                newStatus = AIServiceStatus.active;
                statusMessage = message.isNotEmpty ? message : 'Status: active';
                break;
              case 'pending':
                newStatus = AIServiceStatus.pending;
                statusMessage = message.isNotEmpty ? message : 'Status: pending';
                break;
              case 'expired':
                newStatus = AIServiceStatus.expired;
                statusMessage = message.isNotEmpty ? message : 'Status: expired';
                break;
              case 'inactive':
                newStatus = AIServiceStatus.inactive;
                statusMessage = message.isNotEmpty ? message : 'Status: inactive';
                break;
              case 'notFound':
                newStatus = AIServiceStatus.notFound;
                statusMessage = message.isNotEmpty ? message : 'Status: notFound';
                break;
              default:
                // If WordPress returns unknown/inactive, check trial
                final trialCheck = _checkTrialStatus();
                if (trialCheck != null) {
                  newStatus = AIServiceStatus.trial;
                  statusMessage = trialCheck['message'] as String;
                } else {
                  newStatus = AIServiceStatus.unknown;
                  statusMessage = message.isNotEmpty ? message : 'Status: unknown';
                }
            }
          } else {
            // API error, check trial as fallback
            final trialCheck = _checkTrialStatus();
            if (trialCheck != null) {
              newStatus = AIServiceStatus.trial;
              statusMessage = trialCheck['message'] as String;
            } else {
              newStatus = AIServiceStatus.unknown;
              statusMessage = 'Unable to verify subscription (${response.statusCode})';
            }
          }
        } catch (e) {
          debugPrint('API call error: $e');
          // API error, check trial as fallback
          final trialCheck = _checkTrialStatus();
          if (trialCheck != null) {
            newStatus = AIServiceStatus.trial;
            statusMessage = trialCheck['message'] as String;
          } else {
            newStatus = AIServiceStatus.unknown;
            statusMessage = 'Unable to connect to Dream Cloud. Please check your internet connection.';
          }
        }
      } else {
        // No email provided - check if in trial period
        final trialCheck = _checkTrialStatus();
        if (trialCheck != null) {
          newStatus = AIServiceStatus.trial;
          statusMessage = trialCheck['message'] as String;
        } else {
          newStatus = AIServiceStatus.unknown;
          statusMessage = 'No email provided';
        }
      }
      
      final dcIndex = _services.indexWhere((s) => s.isDreamCloud);
      _services[dcIndex] = _services[dcIndex].copyWith(
        subscriptionEmail: email,
        status: newStatus,
        updatedAt: DateTime.now(),
      );
      
      await _saveServices();
      
      _error = statusMessage; // Using error field to show status message
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> deleteService(String serviceId) async {
    final service = getServiceById(serviceId);
    if (service == null) return false;
    
    // Don't allow deleting Dream Cloud
    if (service.isDreamCloud) {
      _error = 'Dream Cloud AI cannot be removed';
      notifyListeners();
      return false;
    }
    
    // Delete API key
    await _storage.deleteApiKey(serviceId);
    
    _services.removeWhere((s) => s.id == serviceId);
    await _saveServices();
    notifyListeners();
    
    return true;
  }
  
  Future<String?> getApiKey(String serviceId) async {
    return await _storage.getApiKey(serviceId);
  }
  
  List<String> getVoicesForService(String serviceId) {
    final service = getServiceById(serviceId);
    if (service == null) return [];
    return service.type.availableVoices;
  }
  
  Future<void> _saveServices() async {
    await _storage.saveAIServices(_services);
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

