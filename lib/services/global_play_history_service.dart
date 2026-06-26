import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/supabase_embeds.dart';

/// Partie enregistrée sur un jeu non possédé (en attente de liaison).
class OrphanBoardgamePlay {
  final String id;
  final String title;
  final String? bggId;
  final String? imageUrl;
  final BoardgamePlaySession session;

  const OrphanBoardgamePlay({
    required this.id,
    required this.title,
    this.bggId,
    this.imageUrl,
    required this.session,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (bggId != null) 'bgg_id': bggId,
        if (imageUrl != null) 'image_url': imageUrl,
        'session': session.toJson(),
      };

  factory OrphanBoardgamePlay.fromJson(Map<String, dynamic> json) {
    return OrphanBoardgamePlay(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Jeu',
      bggId: json['bgg_id'] as String?,
      imageUrl: json['image_url'] as String?,
      session: BoardgamePlaySession.fromJson(
        Map<String, dynamic>.from(json['session'] as Map),
      ),
    );
  }
}

/// Entrée unifiée pour l'historique global.
class GlobalPlayHistoryEntry {
  final String? itemId;
  final String title;
  final String? imageUrl;
  final String? bggId;
  final BoardgamePlaySession session;
  final int sessionIndex;
  final bool isOrphan;
  final String? orphanId;

  const GlobalPlayHistoryEntry({
    this.itemId,
    required this.title,
    this.imageUrl,
    this.bggId,
    required this.session,
    required this.sessionIndex,
    this.isOrphan = false,
    this.orphanId,
  });

  String get groupKey => itemId ?? bggId ?? title.toLowerCase();
}

class GlobalPlayHistoryService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  String _orphanKey(String userId) => 'orphan_boardgame_plays_$userId';

  Future<List<OrphanBoardgamePlay>> loadOrphans() async {
    final uid = _userId;
    if (uid == null) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orphanKey(uid));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (e) => OrphanBoardgamePlay.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveOrphans(List<OrphanBoardgamePlay> orphans) async {
    final uid = _userId;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _orphanKey(uid),
      jsonEncode(orphans.map((o) => o.toJson()).toList()),
    );
  }

  Future<void> addOrphan(OrphanBoardgamePlay entry) async {
    final list = await loadOrphans();
    list.insert(0, entry);
    await saveOrphans(list);
  }

  Future<List<CollectionItem>> fetchBoardgameItems() async {
    final uid = _userId;
    if (uid == null) return [];
    final rows = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItemDetail)
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false)
        .or('added_by.eq.$uid,location_user_id.eq.$uid')
        .order('title');
    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where((i) => !i.isExpansion)
        .toList();
  }

  Future<List<GlobalPlayHistoryEntry>> loadAllEntries() async {
    final items = await fetchBoardgameItems();
    final orphans = await loadOrphans();
    final entries = <GlobalPlayHistoryEntry>[];

    for (final item in items) {
      final sessions = parseBoardgamePlays(item.metadata);
      for (var i = 0; i < sessions.length; i++) {
        entries.add(
          GlobalPlayHistoryEntry(
            itemId: item.id,
            title: item.title,
            imageUrl: item.imageUrl,
            bggId: item.metadata?['bgg_id']?.toString(),
            session: sessions[i],
            sessionIndex: i,
          ),
        );
      }
    }

    for (final orphan in orphans) {
      entries.add(
        GlobalPlayHistoryEntry(
          title: orphan.title,
          imageUrl: orphan.imageUrl,
          bggId: orphan.bggId,
          session: orphan.session,
          sessionIndex: 0,
          isOrphan: true,
          orphanId: orphan.id,
        ),
      );
    }

    entries.sort((a, b) => b.session.date.compareTo(a.session.date));
    return entries;
  }

  Future<void> saveSessionToItem(
    CollectionItem item,
    List<BoardgamePlaySession> sessions,
  ) async {
    final meta = Map<String, dynamic>.from(item.metadata ?? {});
    meta['boardgame_plays'] = sessions.map((s) => s.toJson()).toList();
    meta['games_played'] = sessions.length;
    await _client
        .from('collection_items')
        .update({
          'metadata': meta,
          'games_played': sessions.length,
        })
        .eq('id', item.id);
  }

  Future<void> linkOrphansToItem(CollectionItem item) async {
    final bggId = item.metadata?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) return;
    final orphans = await loadOrphans();
    final matching =
        orphans.where((o) => o.bggId == bggId).toList(growable: false);
    if (matching.isEmpty) return;

    final sessions = parseBoardgamePlays(item.metadata);
    for (final o in matching) {
      sessions.insert(0, o.session);
    }
    await saveSessionToItem(item, sessions);
    await saveOrphans(
      orphans.where((o) => o.bggId != bggId).toList(),
    );
  }
}

/// Regroupe les parties consécutives d'un même jeu.
class GlobalPlayHistoryGroup {
  final String groupKey;
  final String title;
  final String? imageUrl;
  final List<GlobalPlayHistoryEntry> entries;
  final bool isStreak;

  const GlobalPlayHistoryGroup({
    required this.groupKey,
    required this.title,
    this.imageUrl,
    required this.entries,
    required this.isStreak,
  });
}

List<GlobalPlayHistoryGroup> groupPlayHistoryEntries(
  List<GlobalPlayHistoryEntry> entries,
) {
  if (entries.isEmpty) return [];
  final groups = <GlobalPlayHistoryGroup>[];
  var i = 0;
  while (i < entries.length) {
    final key = entries[i].groupKey;
    final batch = <GlobalPlayHistoryEntry>[entries[i]];
    var j = i + 1;
    while (j < entries.length && entries[j].groupKey == key) {
      batch.add(entries[j]);
      j++;
    }
    groups.add(
      GlobalPlayHistoryGroup(
        groupKey: key,
        title: entries[i].title,
        imageUrl: entries[i].imageUrl,
        entries: batch,
        isStreak: batch.length > 1,
      ),
    );
    i = j;
  }
  return groups;
}
