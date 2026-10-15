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
  /// Compte ami de l'app associé à ce joueur (partage des parties).
  final String? friendProfileId;
  final String? friendUsername;

  const PlayerIdentity({
    required this.id,
    required this.names,
    required this.displayName,
    this.isMe = false,
    this.friendProfileId,
    this.friendUsername,
  });

  bool get isLinkedToFriend =>
      friendProfileId != null && friendProfileId!.isNotEmpty;

  String get primary => displayName.trim().isNotEmpty
      ? displayName.trim()
      : (names.isEmpty ? '' : names.first);

  Map<String, dynamic> toJson() => {
        'id': id,
        'names': names,
        'displayName': displayName,
        'isMe': isMe,
        if (isLinkedToFriend) 'friendProfileId': friendProfileId,
        if (isLinkedToFriend && friendUsername != null)
          'friendUsername': friendUsername,
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
      friendProfileId: _nonEmpty(json['friendProfileId']),
      friendUsername: _nonEmpty(json['friendUsername']),
    );
  }

  static String? _nonEmpty(Object? raw) {
    final t = raw?.toString().trim();
    return t == null || t.isEmpty ? null : t;
  }

  PlayerIdentity copyWith({
    List<String>? names,
    String? displayName,
    bool? isMe,
    String? friendProfileId,
    String? friendUsername,
    bool clearFriend = false,
  }) {
    return PlayerIdentity(
      id: id,
      names: names ?? this.names,
      displayName: displayName ?? this.displayName,
      isMe: isMe ?? this.isMe,
      friendProfileId:
          clearFriend ? null : (friendProfileId ?? this.friendProfileId),
      friendUsername:
          clearFriend ? null : (friendUsername ?? this.friendUsername),
    );
  }
}

/// Joueur d'une partie lié à un compte ami.
class LinkedFriendPlayer {
  final String playerName;
  final String profileId;
  final String username;

  const LinkedFriendPlayer({
    required this.playerName,
    required this.profileId,
    required this.username,
  });
}

/// Joueurs de [players] liés à un ami (hors « moi »), un seul par compte.
List<LinkedFriendPlayer> linkedFriendsAmong(
  Iterable<String> players,
  Iterable<PlayerIdentity> identities,
) {
  final out = <LinkedFriendPlayer>[];
  final seenProfiles = <String>{};
  for (final raw in players) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty) continue;
    for (final id in identities) {
      if (id.isMe || !id.isLinkedToFriend) continue;
      final hit = id.names.any((n) => n.toLowerCase() == lower) ||
          id.displayName.toLowerCase() == lower;
      if (!hit) continue;
      if (seenProfiles.add(id.friendProfileId!)) {
        out.add(
          LinkedFriendPlayer(
            playerName: raw.trim(),
            profileId: id.friendProfileId!,
            username: id.friendUsername ?? id.primary,
          ),
        );
      }
      break;
    }
  }
  return out;
}

/// Lie [name] au compte ami (crée l'identité si besoin). Un compte ami
/// n'est rattaché qu'à une seule identité à la fois.
List<PlayerIdentity> applyFriendLink(
  List<PlayerIdentity> identities, {
  required String name,
  required String profileId,
  required String username,
  required String newId,
}) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return identities;
  var found = false;
  final next = <PlayerIdentity>[];
  for (final id in identities) {
    final hit = id.names.any((n) => n.toLowerCase() == lower) ||
        id.displayName.toLowerCase() == lower;
    if (hit) {
      found = true;
      next.add(id.copyWith(friendProfileId: profileId, friendUsername: username));
    } else if (id.friendProfileId == profileId) {
      next.add(id.copyWith(clearFriend: true));
    } else {
      next.add(id);
    }
  }
  if (!found) {
    next.add(
      PlayerIdentity(
        id: newId,
        names: [name.trim()],
        displayName: name.trim(),
        friendProfileId: profileId,
        friendUsername: username,
      ),
    );
  }
  return next;
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
    String? friendProfileId;
    String? friendUsername;

    void addName(String n) {
      if (mergedSeen.add(n.toLowerCase())) merged.add(n);
    }

    for (final g in _identities) {
      final hits = g.names.any((n) => touchKeys.contains(n.toLowerCase())) ||
          touchKeys.contains(g.displayName.toLowerCase());
      if (hits) {
        wasMe = wasMe || g.isMe;
        if (friendProfileId == null && g.isLinkedToFriend) {
          friendProfileId = g.friendProfileId;
          friendUsername = g.friendUsername;
        }
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
      friendProfileId: (wasMe || isMe) ? null : friendProfileId,
      friendUsername: (wasMe || isMe) ? null : friendUsername,
    );
    _identities = [...nextKeep, group];
    await _persist();
    return group;
  }

  /// Associe un pseudo à un compte ami (« Cette personne est dans ma liste d'amis »).
  Future<void> linkFriend(
    String name, {
    required String profileId,
    required String username,
  }) async {
    await ensureLoaded();
    _identities = applyFriendLink(
      _identities,
      name: name,
      profileId: profileId,
      username: username,
      newId: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await _persist();
  }

  Future<void> unlinkFriend(String identityId) async {
    await ensureLoaded();
    _identities = _identities
        .map((g) => g.id == identityId ? g.copyWith(clearFriend: true) : g)
        .toList();
    await _persist();
  }

  List<LinkedFriendPlayer> linkedFriendsIn(Iterable<String> players) =>
      linkedFriendsAmong(players, _identities);

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

  /// Efface toutes les identités locales (export / suppression de compte).
  Future<void> resetAllLocalData() async {
    _identities = [];
    _loaded = true;
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
