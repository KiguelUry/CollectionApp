import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/holder_label_utils.dart';

/// Historique local des lieux saisis manuellement (« Autre ») par groupe ou utilisateur.
class HolderPlaceHistoryService {
  static String _groupKey(String groupId) => 'holder_places_$groupId';
  static String _personalKey(String userId) => 'holder_places_user_$userId';

  static Future<List<String>> loadForGroups(
    Iterable<String> groupIds, {
    String? personalUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    final out = <String>[];

    void add(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      final key = v.toLowerCase();
      if (seen.add(key)) out.add(v);
    }

    void readKey(String key) {
      final raw = prefs.getString(key);
      if (raw == null) return;
      try {
        final list = (jsonDecode(raw) as List).whereType<String>().toList();
        for (final e in list) {
          if (e.trim().isNotEmpty) add(e.trim());
        }
      } catch (_) {}
    }

    for (final gid in groupIds) {
      readKey(_groupKey(gid));
    }
    if (groupIds.isEmpty && personalUserId != null) {
      readKey(_personalKey(personalUserId));
    }
    return out;
  }

  static Future<void> saveForGroups(
    Iterable<String> groupIds,
    String displayLabel, {
    String? personalUserId,
  }) async {
    final stored = holderLabelStorageValue(displayLabel).trim();
    if (stored.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();

    Future<void> writeKey(String key) async {
      final existing = <String>[];
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          existing.addAll(
            (jsonDecode(raw) as List).whereType<String>().where(
                  (e) => e.trim().isNotEmpty,
                ),
          );
        } catch (_) {}
      }
      final lower = stored.toLowerCase();
      final next = <String>[
        stored,
        ...existing.where((e) => e.toLowerCase() != lower),
      ].take(24).toList();
      await prefs.setString(key, jsonEncode(next));
    }

    if (groupIds.isEmpty) {
      if (personalUserId != null) {
        await writeKey(_personalKey(personalUserId));
      }
      return;
    }
    for (final gid in groupIds) {
      await writeKey(_groupKey(gid));
    }
  }

  /// Retire un lieu des suggestions pour les groupes donnés.
  static Future<void> removeForGroups(
    Iterable<String> groupIds,
    String displayLabel, {
    String? personalUserId,
  }) async {
    final target = holderLabelStorageValue(
      formatManualHolderLabel(displayLabel),
    ).trim().toLowerCase();
    if (target.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();

    Future<void> removeKey(String key) async {
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

    if (groupIds.isEmpty) {
      if (personalUserId != null) {
        await removeKey(_personalKey(personalUserId));
      }
      return;
    }
    for (final gid in groupIds) {
      await removeKey(_groupKey(gid));
    }
  }
}
