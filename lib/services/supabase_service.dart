import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://lfpzverpjlcuobmgejwv.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_ERb-xF0Fcro3_xrQsNoGrQ_kLbo7hq2';
  
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }
  
  static SupabaseClient get client => Supabase.instance.client;
  
  static GoTrueClient get auth => client.auth;
  
  static User? get currentUser => auth.currentUser;
  
  static bool get isAuthenticated => currentUser != null;
  
  static Stream<AuthState> get authStateChanges => auth.onAuthStateChange;
}

