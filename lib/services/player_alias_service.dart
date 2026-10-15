import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Identité joueur : un ou plusieurs pseudos = la même personne.
class PlayerIdentity {
  final String id;
  /// Pseudos liés (orthographes telles qu'écrites dans l'historique).
  final List<String> names;
  /// Nom affiché dans classements / après renommage.
  final String displayName;
  /// Cette identité = toi.
  final bool isMe;

  const PlayerIdentity({
    required this.id,
    required this.names,
    required this.displayName,
    this.isMe = false,
  });

  String get primary => displayName.trim().isNotEmpty
      ? displayName.trim()
      : (names.isEmpty ? '' : names.first);

  Map<String, dynamic> toJson() => {
        'id': id,
        'names': names,
        'displayName': displayName,
        'isMe': isMe,
      };

  factory PlayerIdentity.fromJson(Map<String, dynamic> json) {
    final raw = json['names'];
    final names = raw is List
        ? raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final display = json['displayName']?.toString().trim();
    return PlayerIdentity(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      names: names,
      displayName: (display != null && display.isNotEmpty)
          ? display
          : (names.isNotEmpty ? names.first : ''),
      isMe: json['isMe'] == true,
    );
  }

  PlayerIdentity copyWith({
    List<String>? names,
    String? displayName,
    bool? isMe,
  }) {
    return PlayerIdentity(
      id: id,
      names: names ?? this.names,
      displayName: displayName ?? this.displayName,
      isMe: isMe ?? this.isMe,
    );
  }
}

/// Clé de comparaison : casse et espaces ignorés (« Lou », « lou », « L ou »).
String aliasCollisionKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Groupes de pseudos qui ne diffèrent que par la casse / les espaces.
/// Les groupes déjà liés à une même identité sont ignorés.
List<List<String>> findAliasCollisions(
  Iterable<String> names, {
  String? Function(String name)? identityIdOf,
}) {
  final buckets = <String, List<String>>{};
  final seenRaw = <String>{};
  for (final raw in names) {
    final t = raw.trim();
    if (t.isEmpty || !seenRaw.add(t)) continue;
    final key = aliasCollisionKey(t);
    if (key.isEmpty) continue;
    buckets.putIfAbsent(key, () => []).add(t);
  }
  final out = <List<String>>[];
  for (final group in buckets.values) {
    if (group.length < 2) continue;
    if (identityIdOf != null) {
      final ids = group.map(identityIdOf).toSet();
      if (ids.length == 1 && ids.first != null) continue;
    }
    out.add(group);
  }
  return out;
}

/// @Deprecated — alias de compat.
typedef PlayerAliasGroup = PlayerIdentity;

/// Lie plusieurs pseudos et fusionne les stats / renomme les parties.
class PlayerAliasService {
  PlayerAliasService._();
  static final instance = PlayerAliasService._();

  static const _prefsKey = 'player_alias_groups_v2';
  static const _prefsKeyLegacy = 'player_alias_groups_v1';

  List<PlayerIdentity> _identities = [];
  bool _loaded = false;

  List<PlayerIdentity> get groups => List.unmodifiable(_identities);
  List<PlayerIdentity> get identities => List.unmodifiable(_identities);

  PlayerIdentity? get meIdentity {
    try {
      return _identities.firstWhere((e) => e.isMe);
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey) ?? prefs.getString(_prefsKeyLegacy);
    if (raw == null || raw.isEmpty) {
      _identities = [];
      _loaded = true;
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _identities = list
          .whereType<Map>()
          .map((e) => PlayerIdentity.fromJson(Map<String, dynamic>.from(e)))
          .where((g) => g.names.isNotEmpty)
          .toList();
    } catch (_) {
      _identities = [];
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_identities.map((g) => g.toJson()).toList()),
    );
  }

  /// Nom canonique pour classements (displayName du groupe, sinon inchangé).
  String canonical(String name) {
    final t = name.trim();
    if (t.isEmpty) return t;
    final lower = t.toLowerCase();
    for (final g in _identities) {
      if (g.names.any((n) => n.toLowerCase() == lower) ||
          g.displayName.toLowerCase() == lower) {
        return g.primary;
      }
    }
    return t;
  }

  List<String> aliasesFor(String name) {
    final t = name.trim();
    if (t.isEmpty) return const [];
    final lower = t.toLowerCase();
    for (final g in _identities) {
      if (g.names.any((n) => n.toLowerCase() == lower) ||
          g.displayName.toLowerCase() == lower) {
        return List<String>.from(g.names);
      }
    }
    return [t];
  }

  PlayerIdentity? identityFor(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final g in _identities) {
      if (g.names.any((n) => n.toLowerCase() == lower) ||
          g.displayName.toLowerCase() == lower) {
        return g;
      }
    }
    return null;
  }

  String displayLabel(String name, {int maxNames = 3}) {
    final id = identityFor(name);
    if (id == null) return name.trim();
    final label = id.primary;
    final extras =
        id.names.where((n) => n.toLowerCase() != label.toLowerCase()).toList();
    if (extras.isEmpty) return id.isMe ? '$label (moi)' : label;
    final shown = extras.take(maxNames).join(' · ');
    final more = extras.length > maxNames ? ' · +${extras.length - maxNames}' : '';
    final me = id.isMe ? ' · moi' : '';
    return '$label ($shown$more)$me';
  }

  /// Crée / fusionne une identité.
  /// [names] = pseudos cochés ; [displayName] = nom à afficher.
  Future<PlayerIdentity> linkNames(
    List<String> names, {
    String? displayName,
    bool isMe = false,
  }) async {
    await ensureLoaded();
    final cleaned = <String>[];
    final seen = <String>{};
    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      if (seen.add(t.toLowerCase())) cleaned.add(t);
    }
    if (cleaned.isEmpty) {
      throw ArgumentError('Sélectionne au moins un nom');
    }

    final touchKeys = cleaned.map((e) => e.toLowerCase()).toSet();
    final keep = <PlayerIdentity>[];
    final merged = <String>[];
    final mergedSeen = <String>{};
    var wasMe = isMe;

    void addName(String n) {
      if (mergedSeen.add(n.toLowerCase())) merged.add(n);
    }

    for (final g in _identities) {
      final hits = g.names.any((n) => touchKeys.contains(n.toLowerCase())) ||
          touchKeys.contains(g.displayName.toLowerCase());
      if (hits) {
        wasMe = wasMe || g.isMe;
        for (final n in g.names) {
          addName(n);
        }
      } else {
        keep.add(isMe ? g.copyWith(isMe: false) : g);
      }
    }
    for (final n in cleaned) {
      addName(n);
    }

    final chosen = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : merged.first;

    if (!mergedSeen.contains(chosen.toLowerCase())) {
      merged.insert(0, chosen);
    }

    // Un seul « moi ».
    final nextKeep = wasMe || isMe
        ? keep.map((g) => g.copyWith(isMe: false)).toList()
        : keep;

    final group = PlayerIdentity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      names: merged,
      displayName: chosen,
      isMe: wasMe || isMe,
    );
    _identities = [...nextKeep, group];
    await _persist();
    return group;
  }

  Future<void> setMe(String identityId) async {
    await ensureLoaded();
    _identities = _identities
        .map((g) => g.copyWith(isMe: g.id == identityId))
        .toList();
    await _persist();
  }

  Future<void> clearMe() async {
    await ensureLoaded();
    _identities = _identities.map((g) => g.copyWith(isMe: false)).toList();
    await _persist();
  }

  Future<void> deleteGroup(String id) async {
    await ensureLoaded();
    _identities = _identities.where((g) => g.id != id).toList();
    await _persist();
  }

  Future<void> unlinkName(String name) async {
    await ensureLoaded();
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return;
    final next = <PlayerIdentity>[];
    for (final g in _identities) {
      final names = g.names.where((n) => n.toLowerCase() != lower).toList();
      if (names.isEmpty) continue;
      var display = g.displayName;
      if (display.toLowerCase() == lower) {
        display = names.first;
      }
      next.add(g.copyWith(names: names, displayName: display));
    }
    _identities = next;
    await _persist();
  }
}
