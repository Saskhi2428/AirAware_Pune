import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over supabase_flutter's real Auth client. No mock/local
/// auth path exists — if Supabase isn't reachable, these calls throw and
/// the UI shows the real error.
class AuthService {
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signUp({required String email, required String password, String? fullName}) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: fullName != null && fullName.isNotEmpty ? {'full_name': fullName} : null,
    );
    if (res.user == null) {
      throw Exception('Sign up did not return a user — check email confirmation settings.');
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPasswordReset(String email) => _client.auth.resetPasswordForEmail(email);

  Future<void> updateProfile({String? fullName}) async {
    if (fullName != null && fullName.isNotEmpty) {
      await _client.auth.updateUser(
        UserAttributes(data: {'full_name': fullName}),
      );
    }
  }
}
