import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _profiles = ProfileService();

  // Inscription : Crée un utilisateur et ajoute son pseudo dans 'profiles'
  Future<void> signUp(String email, String password, String username) async {
    final AuthResponse res = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'username': username.trim()},
    );

    if (res.user != null) {
      final existing = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', res.user!.id)
          .maybeSingle();
      if (existing == null) {
        await _supabase.from('profiles').insert({
          'id': res.user!.id,
          'username': username.trim(),
        });
      }
    }
    await _profiles.ensureCurrentUserProfile();
  }

  // Connexion
  Future<void> signIn(String email, String password) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
    await _profiles.ensureCurrentUserProfile();
  }

  // Déconnexion
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Envoie un e-mail de réinitialisation (lien Supabase Auth).
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw Exception('Indique l\'adresse e-mail du compte');
    }
    await _supabase.auth.resetPasswordForEmail(trimmed);
  }
}
