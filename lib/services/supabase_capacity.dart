import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_mode.dart';

/// Détection quota / surcharge Supabase → mode hors-ligne + SnackBar discret.
class SupabaseCapacity {
  SupabaseCapacity._();

  static bool _snackShownThisSession = false;

  /// Erreurs typiques : Egress / Log Ingestion / plan free saturé / 429 / timeout.
  static bool looksLikeCapacityError(Object error) {
    if (error is PostgrestException) {
      final code = (error.code ?? '').toUpperCase();
      if (code == '429' ||
          code == '502' ||
          code == '503' ||
          code == '504' ||
          code == '402') {
        return true;
      }
      final blob =
          '${error.message} ${error.details} ${error.hint} ${error.code}'
              .toLowerCase();
      return _capacityText(blob);
    }
    final text = error.toString().toLowerCase();
    if (text.contains('timeoutexception') || text.contains('timed out')) {
      return true;
    }
    return _capacityText(text);
  }

  static bool _capacityText(String text) {
    return text.contains('quota') ||
        text.contains('egress') ||
        text.contains('bandwidth') ||
        text.contains('over_capacity') ||
        text.contains('over capacity') ||
        text.contains('resource exhausted') ||
        text.contains('rate limit') ||
        text.contains('too many requests') ||
        text.contains('project paused') ||
        text.contains('payment required') ||
        text.contains('log ingestion') ||
        text.contains('disk io') ||
        text.contains('exceeded');
  }

  /// Marque [OfflineMode] si quota/réseau. Retourne true si dégradé.
  static bool markDegraded(Object error) {
    if (looksLikeCapacityError(error)) {
      OfflineMode.instance.setOffline(true);
      return true;
    }
    return OfflineMode.instance.markIfNetworkError(error);
  }

  /// SnackBar une fois par session (évite le spam au scroll).
  static void showOfflineSnackIfNeeded(BuildContext? context) {
    if (context == null || !context.mounted) return;
    if (!OfflineMode.instance.active || _snackShownThisSession) return;
    _snackShownThisSession = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Serveur surchargé : affichage hors-ligne temporaire.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @visibleForTesting
  static void resetSnackGateForTest() => _snackShownThisSession = false;
}
