import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Règle simplifiée publiée pour la communauté (MVP local + prêt Supabase).
class CommunityRuleEntry {
  final String id;
  final String gameKey;
  final String authorId;
  final String authorName;
  final String language;
  final String title;
  final String body;
  final int likes;
  final Set<String> likedBy;
  final DateTime createdAt;

  const CommunityRuleEntry({
    required this.id,
    required this.gameKey,
    required this.authorId,
    required this.authorName,
    required this.language,
    required this.title,
    required this.body,
    required this.likes,
    required this.likedBy,
    required this.createdAt,
  });

  bool likedByMe(String? userId) =>
      userId != null && likedBy.contains(userId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameKey': gameKey,
        'authorId': authorId,
        'authorName': authorName,
        'language': language,
        'title': title,
        'body': body,
        'likes': likes,
        'likedBy': likedBy.toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory CommunityRuleEntry.fromJson(Map<String, dynamic> json) {
    final likedRaw = json['likedBy'];
    return CommunityRuleEntry(
      id: json['id']?.toString() ?? '',
      gameKey: json['gameKey']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'Anonyme',
      language: json['language']?.toString() ?? 'fr',
      title: json['title']?.toString() ?? 'Règles simplifiées',
      body: json['body']?.toString() ?? '',
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      likedBy: likedRaw is List
          ? likedRaw.map((e) => e.toString()).toSet()
          : <String>{},
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  CommunityRuleEntry copyWith({
    int? likes,
    Set<String>? likedBy,
  }) {
    return CommunityRuleEntry(
      id: id,
      gameKey: gameKey,
      authorId: authorId,
      authorName: authorName,
      language: language,
      title: title,
      body: body,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      createdAt: createdAt,
    );
  }
}

/// Stockage local des règles communauté (en attendant une table Supabase).
class CommunityRulesService {
  CommunityRulesService._();
  static final instance = CommunityRulesService._();

  static const _prefsKey = 'community_rules_v1';
  static const _pinnedKey = 'community_rules_pinned_v1';

  List<CommunityRuleEntry> _all = [];
  /// itemId → community rule ids ajoutées à « Afficher les règles ».
  Map<String, List<String>> _pinnedByItem = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _all = list
            .whereType<Map>()
            .map((e) => CommunityRuleEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      final pinnedRaw = prefs.getString(_pinnedKey);
      if (pinnedRaw != null && pinnedRaw.isNotEmpty) {
        final map = jsonDecode(pinnedRaw) as Map<String, dynamic>;
        _pinnedByItem = map.map(
          (k, v) => MapEntry(
            k,
            v is List ? v.map((e) => e.toString()).toList() : <String>[],
          ),
        );
      }
    } catch (_) {
      _all = [];
      _pinnedByItem = {};
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_all.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(_pinnedKey, jsonEncode(_pinnedByItem));
  }

  static String gameKeyFor({String? bggId, required String title}) {
    final id = bggId?.trim();
    if (id != null && id.isNotEmpty) return 'bgg:$id';
    return 'title:${title.trim().toLowerCase()}';
  }

  Future<List<CommunityRuleEntry>> forGame(String gameKey, {String? language}) async {
    await ensureLoaded();
    var list = _all.where((e) => e.gameKey == gameKey).toList();
    if (language != null && language.isNotEmpty) {
      list = list.where((e) => e.language == language).toList();
    }
    list.sort((a, b) {
      final byLikes = b.likes.compareTo(a.likes);
      if (byLikes != 0) return byLikes;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  Future<CommunityRuleEntry> publish({
    required String gameKey,
    required String language,
    required String title,
    required String body,
  }) async {
    await ensureLoaded();
    final user = Supabase.instance.client.auth.currentUser;
    final entry = CommunityRuleEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}_${user?.id ?? 'anon'}',
      gameKey: gameKey,
      authorId: user?.id ?? 'anon',
      authorName:
          user?.userMetadata?['username']?.toString() ??
          user?.email?.split('@').first ??
          'Moi',
      language: language,
      title: title.trim().isEmpty ? 'Règles simplifiées' : title.trim(),
      body: body,
      likes: 0,
      likedBy: {},
      createdAt: DateTime.now(),
    );
    _all = [..._all, entry];
    await _persist();
    return entry;
  }

  Future<CommunityRuleEntry?> toggleLike(String ruleId) async {
    await ensureLoaded();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    final idx = _all.indexWhere((e) => e.id == ruleId);
    if (idx < 0) return null;
    final entry = _all[idx];
    final liked = Set<String>.from(entry.likedBy);
    if (liked.contains(userId)) {
      liked.remove(userId);
    } else {
      liked.add(userId);
    }
    final next = entry.copyWith(likes: liked.length, likedBy: liked);
    _all = [..._all]..[idx] = next;
    await _persist();
    return next;
  }

  Future<void> pinToItem(String itemId, String ruleId) async {
    await ensureLoaded();
    final list = List<String>.from(_pinnedByItem[itemId] ?? const []);
    if (!list.contains(ruleId)) list.add(ruleId);
    _pinnedByItem[itemId] = list;
    await _persist();
  }

  Future<void> unpinFromItem(String itemId, String ruleId) async {
    await ensureLoaded();
    final list = List<String>.from(_pinnedByItem[itemId] ?? const []);
    list.remove(ruleId);
    _pinnedByItem[itemId] = list;
    await _persist();
  }

  Future<List<CommunityRuleEntry>> pinnedForItem(String itemId) async {
    await ensureLoaded();
    final ids = _pinnedByItem[itemId] ?? const [];
    return ids
        .map((id) {
          try {
            return _all.firstWhere((e) => e.id == id);
          } catch (_) {
            return null;
          }
        })
        .whereType<CommunityRuleEntry>()
        .toList();
  }

  CommunityRuleEntry? byId(String id) {
    try {
      return _all.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }
}
