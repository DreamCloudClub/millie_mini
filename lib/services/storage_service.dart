import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/constants.dart';

class StorageService {
  late SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  // User Profile
  Future<void> saveUserProfile(UserProfile profile) async {
    await _prefs.setString(StorageKeys.userProfile, jsonEncode(profile.toJson()));
  }
  
  Future<UserProfile?> getUserProfile() async {
    try {
      final data = _prefs.getString(StorageKeys.userProfile);
      if (data == null) return null;
      return UserProfile.fromJson(jsonDecode(data));
    } catch (e) {
      // If data is corrupted, clear it
      await clearUserProfile();
      return null;
    }
  }
  
  Future<void> clearUserProfile() async {
    await _prefs.remove(StorageKeys.userProfile);
  }
  
  // Agents
  Future<void> saveAgents(List<Agent> agents) async {
    final data = agents.map((a) => a.toJson()).toList();
    await _prefs.setString(StorageKeys.agents, jsonEncode(data));
  }
  
  Future<List<Agent>> getAgents() async {
    final data = _prefs.getString(StorageKeys.agents);
    if (data == null) {
      // Return default agent if none exist
      return [Agent.defaultAgent()];
    }
    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((d) => Agent.fromJson(d)).toList();
  }
  
  Future<void> setActiveAgentId(String agentId) async {
    await _prefs.setString(StorageKeys.activeAgentId, agentId);
  }
  
  Future<String?> getActiveAgentId() async {
    return _prefs.getString(StorageKeys.activeAgentId);
  }
  
  // Personalities
  Future<void> savePersonalities(List<Personality> personalities) async {
    // Only save non-default personalities
    final customPersonalities = personalities.where((p) => !p.isDefault).toList();
    final data = customPersonalities.map((p) => p.toJson()).toList();
    await _prefs.setString(StorageKeys.personalities, jsonEncode(data));
  }
  
  Future<List<Personality>> getPersonalities() async {
    // Always include defaults
    final List<Personality> personalities = [
      Personality.home(),
      Personality.office(),
    ];
    
    final data = _prefs.getString(StorageKeys.personalities);
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      personalities.addAll(decoded.map((d) => Personality.fromJson(d)));
    }
    
    return personalities;
  }
  
  // AI Services
  Future<void> saveAIServices(List<AIService> services) async {
    // Don't save the default Dream Cloud service - it's always added
    final customServices = services.where((s) => !s.isDreamCloud).toList();
    final data = customServices.map((s) => s.toJson()).toList();
    await _prefs.setString(StorageKeys.aiServices, jsonEncode(data));
  }
  
  Future<List<AIService>> getAIServices() async {
    // Always include Dream Cloud
    final List<AIService> services = [AIService.dreamCloud()];
    
    final data = _prefs.getString(StorageKeys.aiServices);
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      services.addAll(decoded.map((d) => AIService.fromJson(d)));
    }
    
    return services;
  }
  
  // Auth
  Future<void> setLoggedIn(bool value) async {
    await _prefs.setBool(StorageKeys.isLoggedIn, value);
  }
  
  Future<bool> isLoggedIn() async {
    return _prefs.getBool(StorageKeys.isLoggedIn) ?? false;
  }
  
  Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: StorageKeys.authToken, value: token);
  }
  
  Future<String?> getAuthToken() async {
    return await _secureStorage.read(key: StorageKeys.authToken);
  }
  
  Future<void> clearAuthToken() async {
    await _secureStorage.delete(key: StorageKeys.authToken);
  }
  
  // API Keys (secure storage)
  Future<void> saveApiKey(String serviceId, String apiKey) async {
    await _secureStorage.write(key: 'api_key_$serviceId', value: apiKey);
  }
  
  Future<String?> getApiKey(String serviceId) async {
    return await _secureStorage.read(key: 'api_key_$serviceId');
  }
  
  Future<void> deleteApiKey(String serviceId) async {
    await _secureStorage.delete(key: 'api_key_$serviceId');
  }
  
  // Porcupine/Picovoice access key (secure storage)
  Future<void> savePorcupineAccessKey(String accessKey) async {
    await _secureStorage.write(key: StorageKeys.porcupineAccessKey, value: accessKey);
  }
  
  Future<String?> getPorcupineAccessKey() async {
    return await _secureStorage.read(key: StorageKeys.porcupineAccessKey);
  }
  
  // Generic string storage (for caching)
  Future<void> saveString(String key, String value) async {
    await _prefs.setString(key, value);
  }
  
  Future<String?> getString(String key) async {
    return _prefs.getString(key);
  }
  
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }
  
  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
    await _secureStorage.deleteAll();
  }
}

