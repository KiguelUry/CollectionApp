import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dernières lignes `collection_items` connues, par utilisateur et par écran.
///
/// Affichage instantané à l'ouverture (mémoire, puis disque), la synchro
/// Supabase remplace ensuite les données en silence.
class CollectionLocalCache {
  CollectionLocalCache._();

  static const _prefix = 'collection_rows_v1';

  /// localStorage web ≈ 5 Mo pour tout le site : on ne stocke pas au-delà.
  static const _maxChars = 1500000;

  static final _memory = <String, List<Map<String, dynamic>>>{};
  static final _pendingWrites = <String, Timer>{};

  static String _key(String userId, String scope) => '$_prefix:$userId:$scope';

  /// Lecture synchrone (session en cours uniquement).
  static List<Map<String, dynamic>>? peek(String userId, String scope) =>
      _memory[_key(userId, scope)];

  static Future<List<Map<String, dynamic>>?> read(
    String userId,
    String scope,
  ) async {
    final key = _key(userId, scope);
    final mem = _memory[key];
    if (mem != null) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final rows = [
        for (final r in decoded)
          if (r is Map) Map<String, dynamic>.from(r),
      ];
      _memory[key] = rows;
      return rows;
    } catch (e) {
      if (kDebugMode) debugPrint('CollectionLocalCache read: $e');
      return null;
    }
  }

  /// Mémoire immédiate ; disque regroupé (une écriture par seconde max).
  static void write(
    String userId,
    String scope,
    List<Map<String, dynamic>> rows,
  ) {
    final key = _key(userId, scope);
    _memory[key] = rows;
    _pendingWrites[key]?.cancel();
    _pendingWrites[key] = Timer(const Duration(seconds: 1), () async {
      _pendingWrites.remove(key);
      try {
        final encoded = jsonEncode(rows);
        final prefs = await SharedPreferences.getInstance();
        if (encoded.length > _maxChars) {
          await prefs.remove(key);
          return;
        }
        await prefs.setString(key, encoded);
      } catch (e) {
        if (kDebugMode) debugPrint('CollectionLocalCache write: $e');
      }
    });
  }

  /// À appeler à la déconnexion (appareil partagé).
  static Future<void> clearAll() async {
    _memory.clear();
    for (final t in _pendingWrites.values) {
      t.cancel();
    }
    _pendingWrites.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
