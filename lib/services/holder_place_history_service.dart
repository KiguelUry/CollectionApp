import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/holder_label_utils.dart';

/// Historique local des lieux saisis manuellement (« Autre ») par groupe.
class HolderPlaceHistoryService {
  static String _key(String groupId) => 'holder_places_$groupId';

  static Future<List<String>> loadForGroups(Iterable<String> groupIds) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    final out = <String>[];

    void add(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      final key = v.toLowerCase();
      if (seen.add(key)) out.add(v);
    }

    for (final gid in groupIds) {
      final raw = prefs.getString(_key(gid));
      if (raw == null) continue;
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          if (e is String) add(e);
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<void> saveForGroups(
    Iterable<String> groupIds,
    String displayLabel,
  ) async {
    final stored = holderLabelStorageValue(displayLabel).trim();
    if (stored.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final gid in groupIds) {
      final key = _key(gid);
      final existing = <String>[];
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          for (final e in jsonDecode(raw) as List) {
            if (e is String && e.trim().isNotEmpty) existing.add(e.trim());
          }
        } catch (_) {}
      }
      final lower = stored.toLowerCase();
      final next = <String>[
        stored,
        ...existing.where((e) => e.toLowerCase() != lower),
      ].take(24).toList();
      await prefs.setString(key, jsonEncode(next));
    }
  }

  /// Retire un lieu des suggestions pour les groupes donnés.
  static Future<void> removeForGroups(
    Iterable<String> groupIds,
    String displayLabel,
  ) async {
    final target = holderLabelStorageValue(
      formatManualHolderLabel(displayLabel),
    ).trim().toLowerCase();
    if (target.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final gid in groupIds) {
      final key = _key(gid);
      final raw = prefs.getString(key);
      if (raw == null) continue;
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
}
