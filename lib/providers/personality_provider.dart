import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

class PersonalityProvider extends ChangeNotifier {
  final StorageService _storage;
  final _uuid = const Uuid();
  
  List<Personality> _personalities = [];
  bool _isLoading = false;
  String? _error;
  
  PersonalityProvider(this._storage);
  
  List<Personality> get personalities => _personalities;
  List<Personality> get defaultPersonalities => 
      _personalities.where((p) => p.isDefault).toList();
  List<Personality> get customPersonalities => 
      _personalities.where((p) => !p.isDefault).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  /// Always get current user ID from Supabase
  String? get _userId => SupabaseConfig.currentUser?.id;
  
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Always start with defaults
      _personalities = [
        Personality.home(),
        Personality.office(),
      ];
      
      // Load custom personalities from Supabase
      if (_userId != null) {
        await _loadPersonalitiesFromSupabase();
      }
      
      // Fallback to local storage if no custom loaded
      if (customPersonalities.isEmpty) {
        final localPersonalities = await _storage.getPersonalities();
        for (final p in localPersonalities) {
          if (!p.isDefault && !_personalities.any((existing) => existing.id == p.id)) {
            _personalities.add(p);
          }
        }
      }
    } catch (e) {
      debugPrint('Personality init error: $e');
      _error = 'Failed to load personalities';
      // Ensure defaults exist even on error
      if (_personalities.isEmpty) {
        _personalities = [
          Personality.home(),
          Personality.office(),
        ];
      }
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  Future<void> _loadPersonalitiesFromSupabase() async {
    if (_userId == null) return;
    
    try {
      final response = await SupabaseConfig.client
          .from('personalities')
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);
      
      if (response != null && (response as List).isNotEmpty) {
        for (final row in response) {
          final personality = Personality(
            id: row['id'] as String,
            name: row['name'] as String,
            behaviorPrompt: row['behavior_prompt'] as String,
            isDefault: false,
            createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
            updatedAt: DateTime.tryParse(row['updated_at'] ?? '') ?? DateTime.now(),
          );
          
          if (!_personalities.any((p) => p.id == personality.id)) {
            _personalities.add(personality);
          }
        }
        
        // Save to local storage for offline access
        await _storage.savePersonalities(_personalities);
      }
    } catch (e) {
      debugPrint('Error loading personalities from Supabase: $e');
    }
  }
  
  Personality? getPersonalityById(String id) {
    try {
      return _personalities.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
  
  Future<Personality> createPersonality({
    required String name,
    required String behaviorPrompt,
  }) async {
    final now = DateTime.now();
    final personality = Personality(
      id: _uuid.v4(),
      name: name,
      behaviorPrompt: behaviorPrompt,
      isDefault: false,
      createdAt: now,
      updatedAt: now,
    );
    
    _personalities.add(personality);
    await _savePersonalities();
    
    // Sync to Supabase
    await _syncPersonalityToSupabase(personality);
    
    notifyListeners();
    
    return personality;
  }
  
  Future<Personality> customizePersonality({
    required String sourceId,
    required String newName,
    required String behaviorPrompt,
  }) async {
    // Find source personality
    final source = getPersonalityById(sourceId);
    if (source == null) {
      throw Exception('Source personality not found');
    }
    
    // Create customized version
    return createPersonality(
      name: newName,
      behaviorPrompt: behaviorPrompt,
    );
  }
  
  Future<void> updatePersonality({
    required String personalityId,
    String? name,
    String? behaviorPrompt,
  }) async {
    final index = _personalities.indexWhere((p) => p.id == personalityId);
    if (index == -1) return;
    
    final personality = _personalities[index];
    
    // Don't allow editing default personalities
    if (personality.isDefault) {
      _error = 'Default personalities cannot be edited';
      notifyListeners();
      return;
    }
    
    final updated = personality.copyWith(
      name: name,
      behaviorPrompt: behaviorPrompt,
      updatedAt: DateTime.now(),
    );
    
    _personalities[index] = updated;
    
    await _savePersonalities();
    
    // Sync to Supabase
    await _syncPersonalityToSupabase(updated);
    
    notifyListeners();
  }
  
  Future<bool> deletePersonality(String personalityId) async {
    final personality = getPersonalityById(personalityId);
    if (personality == null) return false;
    
    // Don't allow deleting default personalities
    if (personality.isDefault) {
      _error = 'Default personalities cannot be deleted';
      notifyListeners();
      return false;
    }
    
    _personalities.removeWhere((p) => p.id == personalityId);
    await _savePersonalities();
    
    // Delete from Supabase
    await _deletePersonalityFromSupabase(personalityId);
    
    notifyListeners();
    
    return true;
  }
  
  Future<void> _savePersonalities() async {
    await _storage.savePersonalities(_personalities);
  }
  
  Future<void> _syncPersonalityToSupabase(Personality personality) async {
    if (_userId == null || personality.isDefault) return;
    
    try {
      await SupabaseConfig.client.from('personalities').upsert({
        'id': personality.id,
        'user_id': _userId,
        'name': personality.name,
        'behavior_prompt': personality.behaviorPrompt,
        'is_default': false,
        'created_at': personality.createdAt.toIso8601String(),
        'updated_at': personality.updatedAt.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error syncing personality to Supabase: $e');
    }
  }
  
  Future<void> _deletePersonalityFromSupabase(String personalityId) async {
    if (_userId == null) return;
    
    try {
      await SupabaseConfig.client
          .from('personalities')
          .delete()
          .eq('id', personalityId);
    } catch (e) {
      debugPrint('Error deleting personality from Supabase: $e');
    }
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
