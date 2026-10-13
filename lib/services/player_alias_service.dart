import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Groupe d'alias : plusieurs noms = la même personne.
class PlayerAliasGroup {
  final String id;
  final List<String> names;

  const PlayerAliasGroup({required this.id, required this.names});

  String get primary => names.isEmpty ? '' : names.first;

  Map<String, dynamic> toJson() => {'id': id, 'names': names};

  factory PlayerAliasGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['names'];
    final names = raw is List
        ? raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return PlayerAliasGroup(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      names: names,
    );
  }
}

/// Lie plusieurs pseudos (Kiki / Kig / Goran) à la même personne.
class PlayerAliasService {
  PlayerAliasService._();
  static final instance = PlayerAliasService._();

  static const _prefsKey = 'player_alias_groups_v1';

  List<PlayerAliasGroup> _groups = [];
  bool _loaded = false;

  List<PlayerAliasGroup> get groups => List.unmodifiable(_groups);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _groups = [];
      _loaded = true;
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _groups = list
          .whereType<Map>()
          .map((e) => PlayerAliasGroup.fromJson(Map<String, dynamic>.from(e)))
          .where((g) => g.names.length >= 2)
          .toList();
    } catch (_) {
      _groups = [];
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_groups.map((g) => g.toJson()).toList()),
    );
  }

  /// Nom canonique (premier du groupe) ou le nom tel quel.
  String canonical(String name) {
    final t = name.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    for (final g in _groups) {
      if (g.names.any((n) => n.toLowerCase() == lower)) {
        return g.primary;
      }
    }
    return t;
  }

  /// Tous les alias d'une personne (ou juste [name]).
  List<String> aliasesFor(String name) {
    final t = name.trim();
    if (t.isEmpty) return const [];
    final lower = t.toLowerCase();
    for (final g in _groups) {
      if (g.names.any((n) => n.toLowerCase() == lower)) {
        return List<String>.from(g.names);
      }
    }
    return [t];
  }

  /// Libellé compact pour une ligne de liste : « Kiki · Kig · Goran ».
  String displayLabel(String name, {int maxNames = 3}) {
    final aliases = aliasesFor(name);
    if (aliases.length <= 1) return name.trim();
    if (aliases.length <= maxNames) return aliases.join(' · ');
    return '${aliases.take(maxNames - 1).join(' · ')} · +${aliases.length - (maxNames - 1)}';
  }

  Future<PlayerAliasGroup> linkNames(List<String> names) async {
    await ensureLoaded();
    final cleaned = <String>[];
    final seen = <String>{};
    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) cleaned.add(t);
    }
    if (cleaned.length < 2) {
      throw ArgumentError('Il faut au moins 2 noms à lier');
    }

    // Fusionner avec groupes existants qui touchent ces noms.
    final touchKeys = cleaned.map((e) => e.toLowerCase()).toSet();
    final keep = <PlayerAliasGroup>[];
    final merged = <String>[];
    final mergedSeen = <String>{};
    void addName(String n) {
      final k = n.toLowerCase();
      if (mergedSeen.add(k)) merged.add(n);
    }

    for (final g in _groups) {
      final hits = g.names.any((n) => touchKeys.contains(n.toLowerCase()));
      if (hits) {
        for (final n in g.names) {
          addName(n);
        }
      } else {
        keep.add(g);
      }
    }
    for (final n in cleaned) {
      addName(n);
    }

    final group = PlayerAliasGroup(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      names: merged,
    );
    _groups = [...keep, group];
    await _persist();
    return group;
  }

  Future<void> unlinkName(String name) async {
    await ensureLoaded();
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return;
    final next = <PlayerAliasGroup>[];
    for (final g in _groups) {
      final names = g.names.where((n) => n.toLowerCase() != lower).toList();
      if (names.length >= 2) {
        next.add(PlayerAliasGroup(id: g.id, names: names));
      }
    }
    _groups = next;
    await _persist();
  }

  Future<void> deleteGroup(String id) async {
    await ensureLoaded();
    _groups = _groups.where((g) => g.id != id).toList();
    await _persist();
  }
}
