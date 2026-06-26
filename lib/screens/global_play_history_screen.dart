import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/global_play_history_service.dart';
import '../widgets/boardgame_play_history_panel.dart';
import '../widgets/bgg_network_image.dart';

/// Historique global des parties (tous jeux confondus).
class GlobalPlayHistoryScreen extends StatefulWidget {
  const GlobalPlayHistoryScreen({super.key});

  @override
  State<GlobalPlayHistoryScreen> createState() =>
      _GlobalPlayHistoryScreenState();
}

class _GlobalPlayHistoryScreenState extends State<GlobalPlayHistoryScreen> {
  final _service = GlobalPlayHistoryService();
  bool _loading = true;
  List<GlobalPlayHistoryGroup> _groups = [];
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _service.loadAllEntries();
    if (!mounted) return;
    setState(() {
      _groups = groupPlayHistoryEntries(entries);
      _loading = false;
    });
  }

  Future<void> _openEntry(GlobalPlayHistoryEntry entry) async {
    CollectionItem item;
    if (entry.itemId != null) {
      final items = await _service.fetchBoardgameItems();
      item = items.firstWhere(
        (i) => i.id == entry.itemId,
        orElse: () => _fallbackItem(entry),
      );
    } else {
      item = _fallbackItem(entry);
    }

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgamePlaySessionPage(
          item: item,
          initial: entry.session,
        ),
        fullscreenDialog: true,
      ),
    );
    _load();
  }

  CollectionItem _fallbackItem(GlobalPlayHistoryEntry entry) {
    return CollectionItem(
      id: entry.itemId ?? 'orphan_${entry.bggId ?? entry.title}',
      title: entry.title,
      category: CollectionCategory.boardgame,
      imageUrl: entry.imageUrl,
      isWishlist: false,
      metadata: {
        if (entry.bggId != null) 'bgg_id': entry.bggId,
      },
    );
  }

  Future<void> _addSession() async {
    final picked = await _pickGame();
    if (picked == null || !mounted) return;

    final session = await Navigator.push<BoardgamePlaySession>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgamePlaySessionPage(
          item: picked.owned ? picked.item! : picked.orphanItem,
        ),
        fullscreenDialog: true,
      ),
    );
    if (session == null) return;

    if (picked.owned) {
      final sessions = parseBoardgamePlays(picked.item!.metadata);
      await _service.saveSessionToItem(
        picked.item!,
        [session, ...sessions],
      );
    } else {
      await _service.addOrphan(
        OrphanBoardgamePlay(
          id: 'orphan_${DateTime.now().microsecondsSinceEpoch}',
          title: picked.title!,
          bggId: picked.bggId,
          imageUrl: picked.imageUrl,
          session: session,
        ),
      );
    }
    _load();
  }

  Future<_GamePick?> _pickGame() async {
    final items = await _service.fetchBoardgameItems();
    if (!mounted) return null;

    return showModalBottomSheet<_GamePick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final searchController = TextEditingController();
        var bggResults = <Map<String, String>>[];
        var searching = false;

        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> searchBgg(String q) async {
              if (q.trim().length < 2) {
                setModal(() => bggResults = []);
                return;
              }
              setModal(() => searching = true);
              try {
                final r = await BggService.searchGames(q.trim());
                if (ctx.mounted) setModal(() => bggResults = r);
              } catch (_) {
              } finally {
                if (ctx.mounted) setModal(() => searching = false);
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * 0.65,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Pour quel jeu ?',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            labelText: 'Rechercher sur BGG',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: searchBgg,
                        ),
                      ),
                      if (searching)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      Expanded(
                        child: ListView(
                          children: [
                            if (searchController.text.trim().length < 2) ...[
                              const ListTile(
                                title: Text(
                                  'Ma collection',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              for (final item in items)
                                ListTile(
                                  leading: _historyThumb(item.imageUrl),
                                  title: Text(item.title),
                                  onTap: () => Navigator.pop(
                                    ctx,
                                    _GamePick.owned(item),
                                  ),
                                ),
                            ],
                            if (bggResults.isNotEmpty) ...[
                              const ListTile(
                                title: Text(
                                  'Résultats BGG (jeu non possédé)',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              for (final g in bggResults)
                                ListTile(
                                  leading: _historyThumb(g['image_url']),
                                  title: Text(g['title'] ?? 'Jeu'),
                                  subtitle: const Text(
                                    'Partie sans ajouter à la collection',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onTap: () => Navigator.pop(
                                    ctx,
                                    _GamePick.bgg(
                                      bggId: g['id'],
                                      title: g['title'] ?? 'Jeu',
                                      imageUrl: g['image_url'],
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des parties')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSession,
        icon: const Icon(Icons.add),
        label: const Text('Partie'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(
                  child: Text(
                    'Aucune partie enregistrée.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      final group = _groups[index];
                      final expanded = _expanded.contains(group.groupKey);

                      if (group.isStreak && !expanded) {
                        return _StreakTile(
                          group: group,
                          onTap: () =>
                              setState(() => _expanded.add(group.groupKey)),
                        );
                      }

                      if (group.isStreak && expanded) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StreakTile(
                              group: group,
                              expanded: true,
                              onTap: () => setState(
                                () => _expanded.remove(group.groupKey),
                              ),
                            ),
                            for (final entry in group.entries)
                              _EntryTile(
                                entry: entry,
                                dateFmt: dateFmt,
                                title: group.title,
                                nested: true,
                                onTap: () => _openEntry(entry),
                              ),
                          ],
                        );
                      }

                      final entry = group.entries.first;
                      return _EntryTile(
                        entry: entry,
                        dateFmt: dateFmt,
                        title: group.title,
                        imageUrl: group.imageUrl,
                        onTap: () => _openEntry(entry),
                      );
                    },
                  ),
                ),
    );
  }
}

class _GamePick {
  final CollectionItem? item;
  final String? bggId;
  final String? title;
  final String? imageUrl;
  final bool owned;

  const _GamePick._({
    this.item,
    this.bggId,
    this.title,
    this.imageUrl,
    required this.owned,
  });

  factory _GamePick.owned(CollectionItem item) =>
      _GamePick._(item: item, owned: true);

  factory _GamePick.bgg({
    required String? bggId,
    required String title,
    String? imageUrl,
  }) =>
      _GamePick._(
        bggId: bggId,
        title: title,
        imageUrl: imageUrl,
        owned: false,
      );

  CollectionItem get orphanItem => CollectionItem(
        id: 'orphan_$bggId',
        title: title ?? 'Jeu',
        category: CollectionCategory.boardgame,
        imageUrl: imageUrl,
        isWishlist: false,
        metadata: {if (bggId != null) 'bgg_id': bggId},
      );
}

Widget _historyThumb(String? url) {
  if (url == null || url.isEmpty) {
    return const Icon(Icons.extension_outlined);
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: 40,
      height: 40,
      child: BggNetworkImage(url: url, boxedCover: true),
    ),
  );
}

class _StreakTile extends StatelessWidget {
  final GlobalPlayHistoryGroup group;
  final VoidCallback onTap;
  final bool expanded;

  const _StreakTile({
    required this.group,
    required this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _historyThumb(group.imageUrl),
        title: Text(group.title),
        subtitle: Text(
          '${group.entries.length} parties jouées d\'affilée !',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
        onTap: onTap,
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final GlobalPlayHistoryEntry entry;
  final DateFormat dateFmt;
  final String title;
  final VoidCallback onTap;
  final String? imageUrl;
  final bool nested;

  const _EntryTile({
    required this.entry,
    required this.dateFmt,
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.nested = false,
  });

  @override
  Widget build(BuildContext context) {
    final winner = entry.session.effectiveWinner;
    return Card(
      margin: EdgeInsets.only(bottom: 8, left: nested ? 16 : 0),
      child: ListTile(
        leading: nested ? null : _historyThumb(imageUrl),
        title: Text(nested ? dateFmt.format(entry.session.date) : title),
        subtitle: Text(
          [
            if (!nested) dateFmt.format(entry.session.date),
            if (entry.session.summaryLine().isNotEmpty)
              entry.session.summaryLine().replaceAll('\n', ' · '),
            if (winner != null && winner.isNotEmpty) 'Gagnant : $winner',
          ].where((s) => s.isNotEmpty).join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
      ),
    );
  }
}
