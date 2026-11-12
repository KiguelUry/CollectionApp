import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Retient un lien Google/Discord le temps du retour OAuth, puis affiche
/// le message de succès une seule fois.
class OAuthLinkNotice {
  static const _key = 'pending_oauth_link';

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> remember(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, provider);
  }

  static Future<void> showIfPending(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString(_key);
    if (provider == null || !context.mounted) return;
    if (!AuthService().providerLinked(provider)) {
      await prefs.remove(_key);
      return;
    }
    await prefs.remove(_key);
    if (!context.mounted) return;
    final name = provider == 'discord' ? 'Discord' : 'Google';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Compte $name associé avec succès !')),
    );
  }
}
