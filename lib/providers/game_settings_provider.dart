import 'package:flutter/foundation.dart';
import '../models/game_settings.dart';
import '../services/storage_service.dart';

/// Provider for managing game settings (time limits and difficulty)
class GameSettingsProvider extends ChangeNotifier {
  final StorageService _storageService;
  GameSettings _settings = GameSettings.defaults;

  GameSettingsProvider(this._storageService);

  /// Current game settings
  GameSettings get settings => _settings;

  /// Current time limit setting
  TimeLimit get timeLimit => _settings.timeLimit;

  /// Current difficulty setting
  GameDifficulty get difficulty => _settings.difficulty;

  /// Time limit in seconds (null for no limit)
  int? get timeLimitSeconds => _settings.timeLimit.seconds;

  /// Difficulty value for database queries
  String get difficultyValue => _settings.difficulty.dbValue;

  /// Initialize provider by loading settings from storage
  Future<void> init() async {
    try {
      final savedSettings = await _storageService.getGameSettings();
      if (savedSettings != null) {
        _settings = savedSettings;
        debugPrint('GameSettingsProvider: Loaded settings - $_settings');
      } else {
        debugPrint('GameSettingsProvider: Using default settings');
      }
    } catch (e) {
      debugPrint('GameSettingsProvider: Error loading settings: $e');
      // Keep defaults on error
    }
    notifyListeners();
  }

  /// Update settings and persist to storage
  Future<void> updateSettings(GameSettings newSettings) async {
    if (_settings == newSettings) return;

    _settings = newSettings;
    notifyListeners();

    try {
      await _storageService.saveGameSettings(newSettings);
      debugPrint('GameSettingsProvider: Saved settings - $_settings');
    } catch (e) {
      debugPrint('GameSettingsProvider: Error saving settings: $e');
    }
  }

  /// Update just the time limit
  Future<void> setTimeLimit(TimeLimit timeLimit) async {
    await updateSettings(_settings.copyWith(timeLimit: timeLimit));
  }

  /// Update just the difficulty
  Future<void> setDifficulty(GameDifficulty difficulty) async {
    await updateSettings(_settings.copyWith(difficulty: difficulty));
  }

  /// Current display size setting
  DisplaySize get displaySize => _settings.displaySize;

  /// Whether large display mode is enabled
  bool get isLargeDisplay => _settings.displaySize == DisplaySize.large;

  /// Update just the display size
  Future<void> setDisplaySize(DisplaySize displaySize) async {
    await updateSettings(_settings.copyWith(displaySize: displaySize));
  }
}
