import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Inscription : Crée un utilisateur et ajoute son pseudo dans 'profiles'
  Future<void> signUp(String email, String password, String username) async {
    final AuthResponse res = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (res.user != null) {
      // On crée manuellement le profil lié à l'ID de l'utilisateur
      await _supabase.from('profiles').insert({
        'id': res.user!.id,
        'username': username,
      });
    }
  }

  // Connexion
  Future<void> signIn(String email, String password) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  // Déconnexion
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
