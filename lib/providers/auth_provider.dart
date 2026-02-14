import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storage;
  
  bool _isLoading = false;
  bool _isLoggedIn = false;
  UserProfile? _userProfile;
  String? _error;
  
  AuthProvider(this._storage);
  
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  UserProfile? get userProfile => _userProfile;
  String? get error => _error;
  String get username => _userProfile?.username ?? 'User';
  
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Check Supabase auth state
      final user = SupabaseConfig.currentUser;
      
      if (user != null) {
        _isLoggedIn = true;
        
        // Try to load profile from Supabase first
        await _loadProfileFromSupabase(user.id);
        
        // Fallback to local storage if Supabase fails
        if (_userProfile == null) {
          _userProfile = await _storage.getUserProfile();
        }
        
        // If still no profile, create a default one
        if (_userProfile == null) {
          final now = DateTime.now();
          _userProfile = UserProfile(
            id: user.id,
            email: user.email ?? '',
            username: user.email?.split('@').first ?? 'User',
            firstName: '',
            lastName: '',
            createdAt: now,
            updatedAt: now,
          );
          await _storage.saveUserProfile(_userProfile!);
        }
      } else {
        // No Supabase user - clear any stale local data
        _isLoggedIn = false;
        _userProfile = null;
        await _storage.clearUserProfile();
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
      // On error, try local storage as fallback
      _userProfile = await _storage.getUserProfile();
      _isLoggedIn = _userProfile != null;
    }
    
    _isLoading = false;
    notifyListeners();
    
    // Listen for auth state changes
    SupabaseConfig.authStateChanges.listen((data) {
      final event = data.event;
      debugPrint('Auth event: $event');
      
      if (event == AuthChangeEvent.signedIn) {
        _handleSignIn(data.session?.user);
      } else if (event == AuthChangeEvent.signedOut) {
        _handleSignOut();
      }
    });
  }
  
  Future<void> _loadProfileFromSupabase(String userId) async {
    try {
      final response = await SupabaseConfig.client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      
      if (response != null) {
        _userProfile = UserProfile(
          id: response['id'] as String,
          email: response['email'] as String? ?? '',
          username: response['username'] as String? ?? 'User',
          firstName: response['first_name'] as String? ?? '',
          lastName: response['last_name'] as String? ?? '',
          pronouns: response['pronouns'] as String?,
          bio: response['bio'] as String?,
          createdAt: DateTime.tryParse(response['created_at'] ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(response['updated_at'] ?? '') ?? DateTime.now(),
        );
        // Also save to local storage for offline access
        await _storage.saveUserProfile(_userProfile!);
      }
    } catch (e) {
      debugPrint('Error loading profile from Supabase: $e');
    }
  }
  
  void _handleSignIn(User? user) async {
    if (user == null) return;
    
    _isLoggedIn = true;
    
    // Load profile from Supabase
    await _loadProfileFromSupabase(user.id);
    
    // Fallback to creating new profile if needed
    if (_userProfile == null) {
      final now = DateTime.now();
      _userProfile = UserProfile(
        id: user.id,
        email: user.email ?? '',
        username: user.email?.split('@').first ?? 'User',
        firstName: '',
        lastName: '',
        createdAt: now,
        updatedAt: now,
      );
      await _storage.saveUserProfile(_userProfile!);
    }
    
    notifyListeners();
  }
  
  void _handleSignOut() async {
    _isLoggedIn = false;
    _userProfile = null;
    await _storage.clearUserProfile();
    notifyListeners();
  }
  
  Future<bool> signUp({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Validate
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Invalid email address');
      }
      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }
      
      // Clear any stale data first
      await _storage.clearUserProfile();
      
      // Sign up with Supabase
      final response = await SupabaseConfig.auth.signUp(
        email: email,
        password: password,
      );
      
      if (response.user == null) {
        throw Exception('Failed to create account. Please try again.');
      }
      
      // Check if email confirmation is required
      if (response.session == null) {
        _error = 'Please check your email to confirm your account.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // Profile should be auto-created by Supabase trigger
      // Wait a moment for trigger to complete
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Load the profile
      await _loadProfileFromSupabase(response.user!.id);
      
      // If trigger didn't create profile, create locally
      if (_userProfile == null) {
        final now = DateTime.now();
        _userProfile = UserProfile(
          id: response.user!.id,
          email: email,
          username: email.split('@').first,
          firstName: '',
          lastName: '',
          createdAt: now,
          updatedAt: now,
        );
        await _storage.saveUserProfile(_userProfile!);
      }
      
      _isLoggedIn = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      debugPrint('SignUp AuthException: ${e.message}');
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('SignUp error: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Invalid email address');
      }
      if (password.isEmpty) {
        throw Exception('Password is required');
      }
      
      // Clear any stale data first
      await _storage.clearUserProfile();
      
      // Sign in with Supabase
      final response = await SupabaseConfig.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user == null) {
        throw Exception('Invalid credentials');
      }
      
      // Load profile from Supabase
      await _loadProfileFromSupabase(response.user!.id);
      
      // Fallback if no profile in Supabase
      if (_userProfile == null) {
        final now = DateTime.now();
        _userProfile = UserProfile(
          id: response.user!.id,
          email: email,
          username: email.split('@').first,
          firstName: '',
          lastName: '',
          createdAt: now,
          updatedAt: now,
        );
        await _storage.saveUserProfile(_userProfile!);
      }
      
      _isLoggedIn = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      debugPrint('Login AuthException: ${e.message}');
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
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
    
    // Don't use _isLoading here - let the UI manage its own loading state
    _error = null;

    try {
      // Update local profile first
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
      
      // Sync to Supabase
      try {
        await SupabaseConfig.client
            .from('user_profiles')
            .update({
              'username': _userProfile!.username,
              'first_name': _userProfile!.firstName,
              'last_name': _userProfile!.lastName,
              'pronouns': _userProfile!.pronouns,
              'bio': _userProfile!.bio,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _userProfile!.id);
      } catch (e) {
        // Log but don't fail - local save succeeded
        debugPrint('Supabase sync error (non-fatal): $e');
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Update profile error: $e');
      _error = 'Failed to save profile';
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> updateEmail(String newEmail) async {
    if (_userProfile == null) return false;
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      if (newEmail.isEmpty || !newEmail.contains('@')) {
        throw Exception('Invalid email address');
      }
      
      // Update email in Supabase Auth
      await SupabaseConfig.auth.updateUser(
        UserAttributes(email: newEmail),
      );
      
      _userProfile = _userProfile!.copyWith(
        email: newEmail,
        updatedAt: DateTime.now(),
      );
      
      await _storage.saveUserProfile(_userProfile!);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      if (currentPassword.isEmpty) {
        throw Exception('Current password is required');
      }
      if (newPassword.length < 6) {
        throw Exception('New password must be at least 6 characters');
      }
      if (newPassword != confirmPassword) {
        throw Exception('Passwords do not match');
      }
      
      // Update password in Supabase
      await SupabaseConfig.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    
    await _storage.clearUserProfile();
    
    _isLoggedIn = false;
    _userProfile = null;
    _isLoading = false;
    notifyListeners();
  }
  
  Future<bool> deleteAccount() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      await SupabaseConfig.auth.signOut();
      await _storage.clearAll();
      
      _isLoggedIn = false;
      _userProfile = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Force clear all local data - useful for debugging
  Future<void> forceReset() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (_) {}
    
    await _storage.clearAll();
    _isLoggedIn = false;
    _userProfile = null;
    _error = null;
    notifyListeners();
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
