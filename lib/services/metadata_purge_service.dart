import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/collection_item_scope.dart';
import '../utils/metadata_slim.dart';

/// Purge one-shot des blobs metadata déjà stockés (base64, stores_prices, etc.).
class MetadataPurgeService {
  static const _prefsKey = 'metadata_slim_purged_v2';

  /// À appeler après login : 1 SELECT léger + updates batchées si nécessaire.
  static Future<void> runOnceIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsKey) == true) {
        if (kDebugMode) {
          debugPrint(
            '[SUPABASE AUDIT] Purge metadata déjà effectuée (skip).',
          );
        }
        return;
      }
      final userId = CollectionItemScope.currentUserId;
      if (userId == null) return;

      final client = Supabase.instance.client;
      final rows = await CollectionItemScope.ownedByUser(
        client.from('collection_items').select('id, metadata'),
        userId: userId,
      );
      final patches = <Map<String, dynamic>>[];
      var bytesBefore = 0;
      var bytesAfter = 0;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final before = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
        final after = slimMetadata(before);
        bytesBefore += utf8.encode(jsonEncode(before)).length;
        bytesAfter += utf8.encode(jsonEncode(after)).length;
        if (!_mapsEqual(before, after)) {
          patches.add({'id': id, 'metadata': after});
        }
      }

      // Chunks de 40 pour rester sous les limites PostgREST.
      for (var i = 0; i < patches.length; i += 40) {
        final chunk = patches.sublist(
          i,
          i + 40 > patches.length ? patches.length : i + 40,
        );
        await client.from('collection_items').upsert(
          chunk,
          onConflict: 'id',
        );
      }

      // Séries livres : mêmes clés lourdes.
      final seriesRows = await client
          .from('book_series')
          .select('id, metadata')
          .eq('owner_id', userId);
      final seriesPatches = <Map<String, dynamic>>[];
      for (final raw in seriesRows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final before = Map<String, dynamic>.from(row['metadata'] as Map? ?? {});
        final after = slimMetadata(before);
        bytesBefore += utf8.encode(jsonEncode(before)).length;
        bytesAfter += utf8.encode(jsonEncode(after)).length;
        if (!_mapsEqual(before, after)) {
          seriesPatches.add({'id': id, 'metadata': after});
        }
      }
      for (var i = 0; i < seriesPatches.length; i += 40) {
        final chunk = seriesPatches.sublist(
          i,
          i + 40 > seriesPatches.length ? seriesPatches.length : i + 40,
        );
        await client.from('book_series').upsert(
          chunk,
          onConflict: 'id',
        );
      }

      await prefs.setBool(_prefsKey, true);
      final savedKb = ((bytesBefore - bytesAfter) / 1024).toStringAsFixed(1);
      final totalCleaned = patches.length + seriesPatches.length;
      if (kDebugMode) {
        debugPrint(
          '[SUPABASE AUDIT] Purge metadata terminée : '
          '$totalCleaned items nettoyés '
          '(~${savedKb} Ko de JSON retirés côté client).',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SUPABASE AUDIT] Purge metadata échouée : $e');
      }
    }
  }

  static bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key)) return false;
      final av = e.value;
      final bv = b[e.key];
      if (av is Map && bv is Map) {
        if (!_mapsEqual(
          Map<String, dynamic>.from(av),
          Map<String, dynamic>.from(bv),
        )) {
          return false;
        }
      } else if (av is List && bv is List) {
        if (av.length != bv.length) return false;
      } else if (av != bv) {
        return false;
      }
    }
    return true;
  }
}
