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
    final customPersonalities =
        personalities.where((p) => !p.isDefault).toList();
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

  // AI Services (simplified - just stores OpenAI config)
  Future<void> saveAIServices(List<AIService> services) async {
    final data = services.map((s) => s.toJson()).toList();
    await _prefs.setString(StorageKeys.aiServices, jsonEncode(data));
  }

  Future<List<AIService>> getAIServices() async {
    final data = _prefs.getString(StorageKeys.aiServices);
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      return decoded.map((d) => AIService.fromJson(d)).toList();
    }
    return [];
  }

  // Auth (simplified - always logged in locally)
  Future<void> setLoggedIn(bool value) async {
    await _prefs.setBool(StorageKeys.isLoggedIn, value);
  }

  Future<bool> isLoggedIn() async {
    return _prefs.getBool(StorageKeys.isLoggedIn) ?? true; // Default to true for local-only
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

  // Notes - local storage
  Future<void> saveNotes(List<Note> notes) async {
    final data = notes.map((n) => n.toJson()).toList();
    await _prefs.setString('notes', jsonEncode(data));
  }

  Future<List<Note>> getNotes() async {
    final data = _prefs.getString('notes');
    if (data == null) return [];
    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((d) => Note.fromJson(d)).toList();
  }

  // Reminders - local storage
  Future<void> saveReminders(List<Reminder> reminders) async {
    final data = reminders.map((r) => r.toJson()).toList();
    await _prefs.setString('reminders', jsonEncode(data));
  }

  Future<List<Reminder>> getReminders() async {
    final data = _prefs.getString('reminders');
    if (data == null) return [];
    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((d) => Reminder.fromJson(d)).toList();
  }

  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
    await _secureStorage.deleteAll();
  }
}
