import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/supabase_embeds.dart';
import 'play_share_service.dart';

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

    entries.sort(
      (a, b) => compareBoardgamePlaySessions(
        a.session,
        a.sessionIndex,
        b.session,
        b.sessionIndex,
      ),
    );
    return entries;
  }

  Future<void> deleteEntry(GlobalPlayHistoryEntry entry) async {
    if (entry.isOrphan) {
      final orphans = await loadOrphans();
      orphans.removeWhere((o) => o.id == entry.orphanId);
      await saveOrphans(orphans);
      return;
    }

    final itemId = entry.itemId;
    if (itemId == null) return;

    final row = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItemDetail)
        .eq('id', itemId)
        .maybeSingle();
    if (row == null) return;

    final item = CollectionItem.fromJson(Map<String, dynamic>.from(row as Map));
    final sessions = parseBoardgamePlays(item.metadata);
    if (entry.sessionIndex < 0 || entry.sessionIndex >= sessions.length) {
      return;
    }
    sessions.removeAt(entry.sessionIndex);
    await saveSessionToItem(item, sessions);
  }

  /// Remplace une session éditée (collection ou orphan).
  Future<void> replaceSession(
    GlobalPlayHistoryEntry entry,
    BoardgamePlaySession updated,
  ) async {
    if (entry.isOrphan) {
      final orphans = await loadOrphans();
      final i = orphans.indexWhere((o) => o.id == entry.orphanId);
      if (i < 0) return;
      orphans[i] = OrphanBoardgamePlay(
        id: orphans[i].id,
        title: orphans[i].title,
        bggId: orphans[i].bggId,
        imageUrl: orphans[i].imageUrl,
        session: updated,
      );
      await saveOrphans(orphans);
      return;
    }

    final itemId = entry.itemId;
    if (itemId == null) return;

    final row = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItemDetail)
        .eq('id', itemId)
        .maybeSingle();
    if (row == null) return;

    final item = CollectionItem.fromJson(Map<String, dynamic>.from(row as Map));
    final sessions = parseBoardgamePlays(item.metadata);
    if (entry.sessionIndex < 0 || entry.sessionIndex >= sessions.length) {
      return;
    }
    sessions[entry.sessionIndex] = updated;
    await saveSessionToItem(item, sessions);
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

  /// Renomme [fromNames] → [toName] dans toutes les parties (collection + orphelins).
  /// Retourne le nombre de sessions touchées.
  Future<int> renamePlayerAcrossHistory({
    required Iterable<String> fromNames,
    required String toName,
  }) async {
    final target = toName.trim();
    if (target.isEmpty) return 0;
    final map = <String, String>{
      for (final n in fromNames)
        if (n.trim().isNotEmpty) n.trim().toLowerCase(): target,
    };
    if (map.isEmpty) return 0;

    var touched = 0;
    final items = await fetchBoardgameItems();
    for (final item in items) {
      final sessions = parseBoardgamePlays(item.metadata);
      if (sessions.isEmpty) continue;
      var dirty = false;
      final next = <BoardgamePlaySession>[];
      for (final s in sessions) {
        final remapped = s.remapPlayerNames(map);
        if (remapped.toJson().toString() != s.toJson().toString()) {
          dirty = true;
          touched++;
        }
        next.add(remapped);
      }
      if (dirty) await saveSessionToItem(item, next);
    }

    final orphans = await loadOrphans();
    var orphanDirty = false;
    final nextOrphans = <OrphanBoardgamePlay>[];
    for (final o in orphans) {
      final remapped = o.session.remapPlayerNames(map);
      if (remapped.toJson().toString() != o.session.toJson().toString()) {
        orphanDirty = true;
        touched++;
        nextOrphans.add(
          OrphanBoardgamePlay(
            id: o.id,
            title: o.title,
            bggId: o.bggId,
            imageUrl: o.imageUrl,
            session: remapped,
          ),
        );
      } else {
        nextOrphans.add(o);
      }
    }
    if (orphanDirty) await saveOrphans(nextOrphans);
    return touched;
  }

  /// Archive les parties d'un jeu avant suppression de l'objet collection.
  Future<void> archivePlaysFromDeletedItem(CollectionItem item) async {
    if (item.category != CollectionCategory.boardgame) return;
    final sessions = parseBoardgamePlays(item.metadata);
    if (sessions.isEmpty) return;

    final orphans = await loadOrphans();
    final bggId = item.metadata?['bgg_id']?.toString();
    final base = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < sessions.length; i++) {
      orphans.insert(
        0,
        OrphanBoardgamePlay(
          id: 'archived_${item.id}_${i}_$base',
          title: item.title,
          bggId: bggId,
          imageUrl: item.imageUrl,
          session: sessions[i],
        ),
      );
    }
    await saveOrphans(orphans);
  }

  /// Rattache une partie orpheline à un jeu de la collection.
  Future<bool> attachOrphanToItem({
    required String orphanId,
    required CollectionItem item,
  }) async {
    final orphans = await loadOrphans();
    final i = orphans.indexWhere((o) => o.id == orphanId);
    if (i < 0) return false;

    final row = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItemDetail)
        .eq('id', item.id)
        .maybeSingle();
    final fresh = row == null
        ? item
        : CollectionItem.fromJson(Map<String, dynamic>.from(row as Map));

    final attachedSession = orphans[i].session;
    final sessions = mergeSessionIntoHistory(
      parseBoardgamePlays(fresh.metadata),
      attachedSession,
    );
    await saveSessionToItem(fresh, sessions);
    orphans.removeAt(i);
    await saveOrphans(orphans);
    unawaited(
      PlayShareService.instance.shareFinishedPlay(
        session: attachedSession,
        gameTitle: fresh.title,
        bggId: fresh.metadata?['bgg_id']?.toString(),
        imageUrl: fresh.imageUrl,
      ),
    );
    return true;
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

/// Ajoute [session] à l'historique et retrie (plus récent en premier).
List<BoardgamePlaySession> mergeSessionIntoHistory(
  List<BoardgamePlaySession> sessions,
  BoardgamePlaySession session,
) {
  final indexed = [
    for (var i = 0; i < sessions.length; i++) (index: i + 1, s: sessions[i]),
    (index: 0, s: session),
  ];
  indexed.sort((a, b) => compareBoardgamePlaySessions(a.s, a.index, b.s, b.index));
  return [for (final e in indexed) e.s];
}

/// Jeux candidats pour rattacher une partie orpheline : même BGG id d'abord,
/// puis titres proches, puis le reste par ordre alphabétique.
List<CollectionItem> rankOrphanAttachCandidates(
  List<CollectionItem> items, {
  required String orphanTitle,
  String? orphanBggId,
}) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final target = norm(orphanTitle);
  int score(CollectionItem item) {
    final bgg = item.metadata?['bgg_id']?.toString();
    if (orphanBggId != null && orphanBggId.isNotEmpty && bgg == orphanBggId) {
      return 0;
    }
    final t = norm(item.title);
    if (t == target) return 1;
    if (target.isNotEmpty &&
        t.isNotEmpty &&
        (t.contains(target) || target.contains(t))) {
      return 2;
    }
    return 3;
  }

  final sorted = List<CollectionItem>.from(items);
  sorted.sort((a, b) {
    final s = score(a).compareTo(score(b));
    if (s != 0) return s;
    return norm(a.title).compareTo(norm(b.title));
  });
  return sorted;
}

/// Regroupe les parties consécutives d'un même jeu.
class GlobalPlayHistoryGroup {
  /// Clé du jeu (partagée par toutes les séries d'un même jeu).
  final String groupKey;

  /// Unique par série : un même jeu peut avoir plusieurs séries non contiguës.
  final String streakKey;
  final String title;
  final String? imageUrl;
  final List<GlobalPlayHistoryEntry> entries;
  final bool isStreak;

  const GlobalPlayHistoryGroup({
    required this.groupKey,
    required this.streakKey,
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
        streakKey: '$key#$i',
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
