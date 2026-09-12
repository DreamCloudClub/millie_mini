import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/storage_service.dart';

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

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Always start with defaults
      _personalities = [
        Personality.home(),
        Personality.office(),
      ];

      // Load custom personalities from local storage
      final localPersonalities = await _storage.getPersonalities();
      for (final p in localPersonalities) {
        if (!p.isDefault &&
            !_personalities.any((existing) => existing.id == p.id)) {
          _personalities.add(p);
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

    notifyListeners();

    return true;
  }

  Future<void> _savePersonalities() async {
    await _storage.savePersonalities(_personalities);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
