import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/holder_label_utils.dart';

/// Préfixe grammatical affiché pour un lieu.
enum PlacePrefix {
  a('À'),
  en('En'),
  au('Au'),
  chez('Chez');

  const PlacePrefix(this.label);
  final String label;

  static PlacePrefix fromRaw(String? raw) {
    return switch ((raw ?? '').toLowerCase().trim()) {
      'en' => PlacePrefix.en,
      'au' => PlacePrefix.au,
      'chez' => PlacePrefix.chez,
      _ => PlacePrefix.a,
    };
  }
}

/// Un foyer relie un lieu à une ou plusieurs personnes.
class Household {
  final String id;
  final String place;
  final PlacePrefix placePrefix;
  final List<String> people;
  /// Comment *moi* j'affiche ce foyer (lieu ou « Chez moi »).
  final bool preferChezMoi;

  const Household({
    required this.id,
    required this.place,
    this.placePrefix = PlacePrefix.a,
    required this.people,
    this.preferChezMoi = false,
  });

  String get placeLabel => '${placePrefix.label} $place';

  Map<String, dynamic> toJson() => {
        'id': id,
        'place': place,
        'place_prefix': placePrefix.name,
        'people': people,
        'prefer_chez_moi': preferChezMoi,
      };

  factory Household.fromJson(Map<String, dynamic> json) {
    final people = json['people'];
    return Household(
      id: json['id']?.toString() ?? '',
      place: json['place']?.toString() ?? '',
      placePrefix: PlacePrefix.fromRaw(json['place_prefix']?.toString()),
      people: people is List
          ? people
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
          : const [],
      preferChezMoi: json['prefer_chez_moi'] == true,
    );
  }

  Household copyWith({
    String? place,
    PlacePrefix? placePrefix,
    List<String>? people,
    bool? preferChezMoi,
  }) {
    return Household(
      id: id,
      place: place ?? this.place,
      placePrefix: placePrefix ?? this.placePrefix,
      people: people ?? this.people,
      preferChezMoi: preferChezMoi ?? this.preferChezMoi,
    );
  }
}

class HouseholdService extends ChangeNotifier {
  HouseholdService._();
  static final instance = HouseholdService._();

  static const _prefsKey = 'households_v2';
  static const _aliasesKey = 'household_person_aliases_v1';

  List<Household> _own = [];
  List<Household> _peers = [];
  /// Pseudos / noms qui me désignent (pour « Chez moi » côté perspective).
  List<String> _myAliases = [];
  bool _loaded = false;

  List<Household> get homes => List.unmodifiable(_own);
  List<String> get myAliases => List.unmodifiable(_myAliases);
  List<Household> get _all => [..._own, ..._peers];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final local = await _readPrefs();
    final remote = await _readOwnRemote();
    if (remote != null) {
      _own = remote;
      if (remote.isEmpty && local.isNotEmpty) {
        _own = local;
        await _writeOwnRemote(local);
      }
    } else {
      _own = local;
    }
    _myAliases = await _readAliases();
    await _cachePrefs(_own);
    _loaded = true;
    notifyListeners();
    await refreshPeers();
  }

  Future<void> save(List<Household> homes) async {
    _own = homes.where((h) => h.place.trim().isNotEmpty).toList();
    _loaded = true;
    await _cachePrefs(_own);
    await _writeOwnRemote(_own);
    notifyListeners();
  }

  Future<void> saveMyAliases(List<String> aliases) async {
    _myAliases = aliases
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_aliasesKey, _myAliases);
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        await client.from('profiles').update({
          'household_aliases': _myAliases,
        }).eq('id', uid);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshPeers() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final memberships = await client
          .from('group_members')
          .select('group_id')
          .eq('profile_id', uid);
      final groupIds = [
        for (final row in memberships as List)
          if (row['group_id'] != null) row['group_id'].toString(),
      ];
      if (groupIds.isEmpty) {
        _peers = [];
        notifyListeners();
        return;
      }
      final members = await client
          .from('group_members')
          .select('profile_id')
          .inFilter('group_id', groupIds);
      final ids = <String>{
        for (final row in members as List)
          if (row['profile_id'] != null && row['profile_id'] != uid)
            row['profile_id'].toString(),
      };
      if (ids.isEmpty) {
        _peers = [];
        notifyListeners();
        return;
      }
      final rows = await client
          .from('profiles')
          .select('households')
          .inFilter('id', ids.toList());
      final peers = <Household>[];
      for (final row in rows as List) {
        peers.addAll(_parseList(row['households']));
      }
      _peers = peers;
      notifyListeners();
    } catch (_) {}
  }

  Future<List<Household>> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _parseList(prefs.getString(_prefsKey) ?? prefs.getString('households_v1'));
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _readAliases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getStringList(_aliasesKey) ?? const [];
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        final row = await client
            .from('profiles')
            .select('household_aliases, username')
            .eq('id', uid)
            .maybeSingle();
        final remote = row?['household_aliases'];
        if (remote is List && remote.isNotEmpty) {
          return remote.map((e) => e.toString()).toList();
        }
        final username = row?['username']?.toString();
        if (local.isEmpty && username != null && username.isNotEmpty) {
          return [username];
        }
      }
      return local;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cachePrefs(List<Household> homes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(homes.map((h) => h.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<List<Household>?> _readOwnRemote() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return null;
      final row = await client
          .from('profiles')
          .select('households')
          .eq('id', uid)
          .maybeSingle();
      return _parseList(row?['households']);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeOwnRemote(List<Household> homes) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client.from('profiles').update({
        'households': homes.map((h) => h.toJson()).toList(),
      }).eq('id', uid);
    } catch (_) {}
  }

  static List<Household> _parseList(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    return [
      for (final row in decoded)
        if (row is Map) Household.fromJson(Map<String, dynamic>.from(row)),
    ].where((h) => h.id.isNotEmpty && h.place.trim().isNotEmpty).toList();
  }

  Household? matchLabel(String? raw) {
    if (!_loaded || raw == null) return null;
    final bare = _bare(raw);
    if (bare.isEmpty) return null;
    for (final home in _all) {
      if (_bare(home.place) == bare) return home;
      for (final person in home.people) {
        if (_bare(person) == bare) return home;
      }
    }
    return null;
  }

  bool _isMe(String bare) {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null && bare == uid.toLowerCase()) return true;
    } catch (_) {
      // Tests / avant init Supabase.
    }
    for (final alias in _myAliases) {
      if (_bare(alias) == bare) return true;
    }
    return bare == 'moi' || bare == 'me';
  }

  /// Affichage selon *ma* perspective : « Chez moi » si je suis du foyer.
  String displayFor(Household home, {String? rawLabel}) {
    final bare = rawLabel == null ? '' : _bare(rawLabel);
    final iAmMember = home.people.any((p) => _isMe(_bare(p))) ||
        home.preferChezMoi && bare.isNotEmpty && _bare(home.place) == bare;
    final iAmReferenced = bare.isNotEmpty && _isMe(bare);
    if (iAmMember || iAmReferenced) {
      // Si le label brut pointe déjà vers moi, ou si je suis dans le foyer
      // et que le jeu est localisé au lieu du foyer → « Chez moi ».
      if (iAmReferenced || home.people.any((p) => _isMe(_bare(p)))) {
        if (bare.isEmpty ||
            _bare(home.place) == bare ||
            home.people.any((p) => _bare(p) == bare)) {
          return 'Chez moi';
        }
      }
    }
    // Préférence d'affichage locale du lieu
    final mine = _own.where((h) => h.id == home.id || _bare(h.place) == _bare(home.place));
    final preferred = mine.isEmpty ? home : mine.first;
    if (preferred.preferChezMoi &&
        preferred.people.any((p) => _isMe(_bare(p)))) {
      return 'Chez moi';
    }
    return preferred.placeLabel;
  }

  static String _bare(String raw) {
    return holderLabelStorageValue(raw).trim().toLowerCase();
  }
}
