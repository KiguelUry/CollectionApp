import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_redirect.dart';
import 'collection_local_cache.dart';
import 'profile_cache_service.dart';
import 'profile_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _profiles = ProfileService();

  /// Inscription. `true` si la session est déjà ouverte.
  /// `false` si Supabase attend le clic sur le lien de confirmation.
  Future<bool> signUp(String email, String password, String username) async {
    final trimmedName = username.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Le surnom est obligatoire');
    }
    if (await _profiles.isUsernameTaken(trimmedName)) {
      throw Exception('Ce surnom est déjà utilisé');
    }
    final AuthResponse res = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': trimmedName,
        'profile_ready': true,
      },
    );

    if (res.session != null && res.user != null) {
      final existing = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', res.user!.id)
          .maybeSingle();
      if (existing == null) {
        await _supabase.from('profiles').insert({
          'id': res.user!.id,
          'username': trimmedName,
        });
      }
      await _profiles.ensureCurrentUserProfile();
      return true;
    }
    return false;
  }

  Future<void> signInWithProvider(OAuthProvider provider) {
    return _supabase.auth.signInWithOAuth(
      provider,
      redirectTo: AuthRedirectConfig.passwordResetRedirectTo(),
      authScreenLaunchMode: _oauthLaunchMode,
    );
  }

  /// Associe Google ou Discord au compte déjà connecté.
  Future<void> linkProvider(OAuthProvider provider) {
    return _supabase.auth.linkIdentity(
      provider,
      redirectTo: AuthRedirectConfig.passwordResetRedirectTo(),
      authScreenLaunchMode: _oauthLaunchMode,
    );
  }

  LaunchMode get _oauthLaunchMode => kIsWeb
      ? LaunchMode.platformDefault
      : LaunchMode.externalApplication;

  Future<void> markProfileReady() {
    return _supabase.auth.updateUser(
      UserAttributes(data: const {'profile_ready': true}),
    );
  }

  bool providerLinked(String provider) {
    final identities = _supabase.auth.currentUser?.identities ?? const [];
    return identities.any((identity) => identity.provider == provider);
  }

  Future<void> updateEmail(String email) async {
    final trimmed = email.trim();
    if (!_emailRegex.hasMatch(trimmed)) {
      throw Exception('L\'adresse e-mail n\'a pas l\'air correcte');
    }
    await _supabase.auth.updateUser(UserAttributes(email: trimmed));
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
    await CollectionLocalCache.clearAll();
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
