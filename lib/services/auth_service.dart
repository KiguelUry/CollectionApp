import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_redirect.dart';
import 'profile_cache_service.dart';
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
    await ProfileCacheService.instance.hydrate();
    await ProfileCacheService.instance.refresh();
  }

  // Déconnexion
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await ProfileCacheService.instance.clear();
  }

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Envoie un e-mail de réinitialisation (lien Supabase Auth).
  Future<void> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw Exception('Indique l\'adresse e-mail du compte');
    }
    if (!_emailRegex.hasMatch(trimmed)) {
      throw Exception('L\'adresse e-mail n\'a pas l\'air correcte');
    }
    await _supabase.auth.resetPasswordForEmail(
      trimmed,
      redirectTo: AuthRedirectConfig.passwordResetRedirectTo(),
    );
  }

  /// Après le lien de recovery : enregistre le nouveau mot de passe.
  Future<void> updatePassword(String newPassword) async {
    final trimmed = newPassword.trim();
    if (trimmed.length < 6) {
      throw Exception('Le mot de passe doit faire au moins 6 caractères');
    }
    await _supabase.auth.updateUser(UserAttributes(password: trimmed));
  }
}
