import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Message utilisateur pour une erreur réseau / API (pas de freeze silencieux).
String networkErrorMessage(Object error) {
  if (error is PostgrestException) {
    final code = error.code ?? '';
    if (code == 'PGRST301' || error.message.contains('JWT')) {
      return 'Session expirée — reconnecte-toi.';
    }
    return error.message.isNotEmpty
        ? error.message
        : 'Erreur serveur (${error.code ?? 'inconnue'})';
  }
  if (error is AuthException) {
    return error.message;
  }
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection refused') ||
      text.contains('ClientException')) {
    return 'Pas de connexion réseau. Vérifie ta connexion et réessaie.';
  }
  if (text.contains('TimeoutException') || text.contains('timed out')) {
    return 'Le serveur met trop de temps à répondre. Réessaie dans un instant.';
  }
  return 'Action impossible pour le moment. Réessaie plus tard.';
}

void showNetworkErrorSnackBar(
  BuildContext context,
  Object error, {
  String? prefix,
}) {
  if (!context.mounted) return;
  final msg = networkErrorMessage(error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(prefix != null ? '$prefix : $msg' : msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ),
  );
}

/// Exécute [action] et affiche un SnackBar en cas d'échec.
Future<T?> runWithNetworkFeedback<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? errorPrefix,
}) async {
  try {
    return await action();
  } catch (e) {
    showNetworkErrorSnackBar(context, e, prefix: errorPrefix);
    return null;
  }
}
