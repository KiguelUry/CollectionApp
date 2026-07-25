import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/holder_label_utils.dart';

/// Historique des lieux saisis manuellement (« Autre »).
/// - Avec groupe(s) : partagé via Supabase (`group_holder_places`).
/// - Sans groupe : local (`SharedPreferences`) par utilisateur.
class HolderPlaceHistoryService {
  static SupabaseClient get _client => Supabase.instance.client;

  static String _groupKey(String groupId) => 'holder_places_$groupId';
  static String _personalKey(String userId) => 'holder_places_user_$userId';
  static String _migratedKey(String groupId) =>
      'holder_places_migrated_$groupId';

  static String _storageLabel(String displayOrRaw) {
    return holderLabelStorageValue(formatManualHolderLabel(displayOrRaw)).trim();
  }

  static String _normalizedLabel(String displayOrRaw) =>
      _storageLabel(displayOrRaw).toLowerCase();

  static Future<List<String>> loadForGroups(
    Iterable<String> groupIds, {
    String? personalUserId,
  }) async {
    final groupList = groupIds.toSet().toList();
    final seen = <String>{};
    final out = <String>[];

    void add(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      final key = v.toLowerCase();
      if (seen.add(key)) out.add(v);
    }

    if (groupList.isNotEmpty) {
      for (final gid in groupList) {
        await _migrateLocalGroupPlacesIfNeeded(gid);
      }
      try {
        final rows = await _client
            .from('group_holder_places')
            .select('label')
            .inFilter('group_id', groupList)
            .order('created_at');
        for (final row in rows as List) {
          add(row['label'] as String? ?? '');
        }
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        for (final gid in groupList) {
          _readLocalKey(prefs, _groupKey(gid), add);
        }
      }
      return out;
    }

    if (personalUserId != null) {
      final prefs = await SharedPreferences.getInstance();
      _readLocalKey(prefs, _personalKey(personalUserId), add);
    }
    return out;
  }

  static Future<void> saveForGroups(
    Iterable<String> groupIds,
    String displayLabel, {
    String? personalUserId,
  }) async {
    final stored = _storageLabel(displayLabel);
    if (stored.isEmpty) return;

    final groupList = groupIds.toSet().toList();
    if (groupList.isEmpty) {
      if (personalUserId != null) {
        await _savePersonal(personalUserId, stored);
      }
      return;
    }

    final uid = _client.auth.currentUser?.id;
    try {
      await _client.from('group_holder_places').upsert(
            groupList
                .map(
                  (gid) => {
                    'group_id': gid,
                    'label': stored,
                    'normalized_label': stored.toLowerCase(),
                    'created_by': ?uid,
                  },
                )
                .toList(),
            onConflict: 'group_id,normalized_label',
          );
    } catch (_) {
      await _saveLocalGroups(groupList, stored);
    }
  }

  /// Retire un lieu des suggestions pour les groupes donnés.
  static Future<void> removeForGroups(
    Iterable<String> groupIds,
    String displayLabel, {
    String? personalUserId,
  }) async {
    final target = _normalizedLabel(displayLabel);
    if (target.isEmpty) return;

    final groupList = groupIds.toSet().toList();
    if (groupList.isEmpty) {
      if (personalUserId != null) {
        await _removePersonal(personalUserId, target);
      }
      return;
    }

    try {
      await _client
          .from('group_holder_places')
          .delete()
          .inFilter('group_id', groupList)
          .eq('normalized_label', target);
    } catch (_) {
      await _removeLocalGroups(groupList, target);
    }
  }

  static Future<void> _migrateLocalGroupPlacesIfNeeded(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey(groupId)) == true) return;

    final raw = prefs.getString(_groupKey(groupId));
    if (raw == null) {
      await prefs.setBool(_migratedKey(groupId), true);
      return;
    }

    final labels = <String>[];
    try {
      labels.addAll(
        (jsonDecode(raw) as List)
            .whereType<String>()
            .map(_storageLabel)
            .where((e) => e.isNotEmpty),
      );
    } catch (_) {}

    if (labels.isNotEmpty) {
      final uid = _client.auth.currentUser?.id;
      try {
        await _client.from('group_holder_places').upsert(
              labels
                  .map(
                    (stored) => {
                      'group_id': groupId,
                      'label': stored,
                      'normalized_label': stored.toLowerCase(),
                      'created_by': ?uid,
                    },
                  )
                  .toList(),
              onConflict: 'group_id,normalized_label',
            );
      } catch (_) {
        return;
      }
    }

    await prefs.remove(_groupKey(groupId));
    await prefs.setBool(_migratedKey(groupId), true);
  }

  static void _readLocalKey(
    SharedPreferences prefs,
    String key,
    void Function(String) add,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).whereType<String>().toList();
      for (final e in list) {
        if (e.trim().isNotEmpty) add(e.trim());
      }
    } catch (_) {}
  }

  static Future<void> _savePersonal(String userId, String stored) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _personalKey(userId);
    final existing = <String>[];
    _readLocalKey(prefs, key, existing.add);
    final lower = stored.toLowerCase();
    final next = <String>[
      stored,
      ...existing.where((e) => e.toLowerCase() != lower),
    ].take(24).toList();
    await prefs.setString(key, jsonEncode(next));
  }

  static Future<void> _saveLocalGroups(
    List<String> groupIds,
    String stored,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final gid in groupIds) {
      final key = _groupKey(gid);
      final existing = <String>[];
      _readLocalKey(prefs, key, existing.add);
      final lower = stored.toLowerCase();
      final next = <String>[
        stored,
        ...existing.where((e) => e.toLowerCase() != lower),
      ].take(24).toList();
      await prefs.setString(key, jsonEncode(next));
    }
  }

  static Future<void> _removePersonal(String userId, String target) async {
    final prefs = await SharedPreferences.getInstance();
    await _removeLocalKey(prefs, _personalKey(userId), target);
  }

  static Future<void> _removeLocalGroups(
    List<String> groupIds,
    String target,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final gid in groupIds) {
      await _removeLocalKey(prefs, _groupKey(gid), target);
    }
  }

  static Future<void> _removeLocalKey(
    SharedPreferences prefs,
    String key,
    String target,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<String>()
          .where((e) => e.trim().toLowerCase() != target)
          .toList();
      if (list.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(list));
      }
    } catch (_) {}
  }
}
