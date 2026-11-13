import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_score_grid.dart';

/// Modèle de score partagé localement (même principe que les règles de la commu).
class CommunityScoreTemplate {
  final String id;
  final String gameKey;
  final String authorId;
  final String authorName;
  final NamedScorePreset preset;
  final int likes;
  final Set<String> likedBy;
  final DateTime createdAt;

  const CommunityScoreTemplate({
    required this.id,
    required this.gameKey,
    required this.authorId,
    required this.authorName,
    required this.preset,
    required this.likes,
    required this.likedBy,
    required this.createdAt,
  });

  bool likedByMe(String? userId) => userId != null && likedBy.contains(userId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameKey': gameKey,
        'authorId': authorId,
        'authorName': authorName,
        'preset': preset.toJson(),
        'likes': likes,
        'likedBy': likedBy.toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory CommunityScoreTemplate.fromJson(Map<String, dynamic> json) {
    final likedRaw = json['likedBy'];
    final presetRaw = json['preset'];
    return CommunityScoreTemplate(
      id: json['id']?.toString() ?? '',
      gameKey: json['gameKey']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'Anonyme',
      preset: presetRaw is Map
          ? (NamedScorePreset.fromJson(Map<String, dynamic>.from(presetRaw)) ??
              const NamedScorePreset(
                name: 'Modèle',
                confrontation: BoardgameConfrontationType.freeForAll,
                template: BoardgameScoreTemplate(),
              ))
          : const NamedScorePreset(
              name: 'Modèle',
              confrontation: BoardgameConfrontationType.freeForAll,
              template: BoardgameScoreTemplate(),
            ),
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      likedBy: likedRaw is List
          ? likedRaw.map((e) => e.toString()).toSet()
          : <String>{},
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class CommunityScoreTemplatesService {
  CommunityScoreTemplatesService._();
  static final instance = CommunityScoreTemplatesService._();

  static const _key = 'community_score_templates_v1';
  static const _pointsKey = 'community_score_template_points_v1';

  Future<List<CommunityScoreTemplate>> forGame(String gameKey) async {
    final all = await _load();
    final list = all.where((e) => e.gameKey == gameKey).toList()
      ..sort((a, b) => b.likes.compareTo(a.likes));
    return list;
  }

  Future<int> pointsFor(String authorId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pointsKey);
    if (raw == null || raw.isEmpty) return 0;
    final map = jsonDecode(raw);
    if (map is! Map) return 0;
    return (map[authorId] as num?)?.toInt() ?? 0;
  }

  Future<void> publish({
    required String gameKey,
    required NamedScorePreset preset,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    final all = await _load();
    all.add(
      CommunityScoreTemplate(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        gameKey: gameKey,
        authorId: user?.id ?? 'local',
        authorName: user?.email?.split('@').first ?? 'Moi',
        preset: preset,
        likes: 0,
        likedBy: const {},
        createdAt: DateTime.now(),
      ),
    );
    await _save(all);
  }

  Future<void> toggleLike(String id) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'local';
    final all = await _load();
    final index = all.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final entry = all[index];
    final liked = Set<String>.from(entry.likedBy);
    final added = liked.add(userId);
    if (!added) liked.remove(userId);
    all[index] = CommunityScoreTemplate(
      id: entry.id,
      gameKey: entry.gameKey,
      authorId: entry.authorId,
      authorName: entry.authorName,
      preset: entry.preset,
      likes: liked.length,
      likedBy: liked,
      createdAt: entry.createdAt,
    );
    await _save(all);
    await _addPoints(entry.authorId, added ? 1 : -1);
  }

  Future<List<CommunityScoreTemplate>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final item in decoded)
        if (item is Map)
          CommunityScoreTemplate.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<void> _save(List<CommunityScoreTemplate> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final entry in all) entry.toJson()]),
    );
  }

  Future<void> _addPoints(String authorId, int delta) async {
    if (authorId.isEmpty || delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pointsKey);
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) map.addAll(decoded.cast<String, dynamic>());
    }
    final next = ((map[authorId] as num?)?.toInt() ?? 0) + delta;
    map[authorId] = next < 0 ? 0 : next;
    await prefs.setString(_pointsKey, jsonEncode(map));
  }

}
