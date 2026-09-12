import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storage;
  final _uuid = const Uuid();

  bool _isLoading = false;
  UserProfile? _userProfile;
  String? _error;

  AuthProvider(this._storage);

  bool get isLoading => _isLoading;
  // Always logged in for local-only app
  bool get isLoggedIn => true;
  UserProfile? get userProfile => _userProfile;
  String? get error => _error;
  String get username => _userProfile?.username ?? 'User';

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try to load existing profile from local storage
      _userProfile = await _storage.getUserProfile();

      // If no profile exists, create a default local user
      if (_userProfile == null) {
        final now = DateTime.now();
        _userProfile = UserProfile(
          id: _uuid.v4(),
          email: '',
          username: 'User',
          firstName: '',
          lastName: '',
          createdAt: now,
          updatedAt: now,
        );
        await _storage.saveUserProfile(_userProfile!);
        debugPrint('Created default local user profile');
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
      // Create default profile on error
      final now = DateTime.now();
      _userProfile = UserProfile(
        id: _uuid.v4(),
        email: '',
        username: 'User',
        firstName: '',
        lastName: '',
        createdAt: now,
        updatedAt: now,
      );
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updateProfile({
    String? username,
    String? firstName,
    String? lastName,
    String? pronouns,
    String? bio,
  }) async {
    if (_userProfile == null) {
      _error = 'No user profile found';
      notifyListeners();
      return false;
    }

    _error = null;

    try {
      // Update local profile
      _userProfile = _userProfile!.copyWith(
        username: username ?? _userProfile!.username,
        firstName: firstName ?? _userProfile!.firstName,
        lastName: lastName ?? _userProfile!.lastName,
        pronouns: pronouns,
        bio: bio,
        updatedAt: DateTime.now(),
      );

      // Save to local storage
      await _storage.saveUserProfile(_userProfile!);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Update profile error: $e');
      _error = 'Failed to save profile';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
