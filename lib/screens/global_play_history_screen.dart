import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/global_play_history_service.dart';
import '../widgets/boardgame_play_history_panel.dart';
import '../widgets/boardgame_ranking_panel.dart';
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
  final _searchController = TextEditingController();
  bool _loading = true;
  int _tabIndex = 0;
  List<GlobalPlayHistoryEntry> _entries = [];
  List<GlobalPlayHistoryGroup> _groups = [];
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GlobalPlayHistoryGroup> get _visibleGroups {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    return _groups
        .where((g) => g.title.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _service.loadAllEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _groups = groupPlayHistoryEntries(entries);
      _loading = false;
    });
  }

  Future<void> _deleteEntry(GlobalPlayHistoryEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette partie ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.deleteEntry(entry);
    _load();
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
      builder: (ctx) => _PickGameBottomSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy', 'fr_FR');
    final allSessions = _entries.map((e) => e.session).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Historique des parties')),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addSession,
              icon: const Icon(Icons.add),
              label: const Text('Partie'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Historique'),
                        icon: Icon(Icons.history_edu, size: 18),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Classement'),
                        icon: Icon(Icons.emoji_events_outlined, size: 18),
                      ),
                    ],
                    selected: {_tabIndex},
                    onSelectionChanged: (s) =>
                        setState(() => _tabIndex = s.first),
                  ),
                ),
                if (_tabIndex == 0 && _groups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Rechercher un jeu',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  FocusScope.of(context).unfocus();
                                },
                              ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    ),
                  ),
                Expanded(
                  child: _tabIndex == 1
                      ? _buildAllTimeRanking(allSessions)
                      : _buildHistoryList(dateFmt),
                ),
              ],
            ),
    );
  }

  Widget _buildAllTimeRanking(List<BoardgamePlaySession> sessions) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'Aucune partie enregistrée.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Text(
            'Classement général (All-Time)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tous jeux confondus — victoires cumulées, départagées par taux de victoire.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          BoardgameRankingPanel(
            sessions: sessions,
            onOpenSession: (index) {
              if (index >= 0 && index < _entries.length) {
                _openEntry(_entries[index]);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(DateFormat dateFmt) {
    if (_groups.isEmpty) {
      return Center(
        child: Text(
          'Aucune partie enregistrée.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    if (_visibleGroups.isEmpty) {
      return Center(
        child: Text(
          'Aucun jeu ne correspond à « ${_searchController.text.trim()} ».',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: _visibleGroups.length,
        itemBuilder: (context, index) {
          final group = _visibleGroups[index];
          final expanded = _expanded.contains(group.groupKey);

          if (group.isStreak && !expanded) {
            return _StreakTile(
              group: group,
              onTap: () => setState(() => _expanded.add(group.groupKey)),
            );
          }

          if (group.isStreak && expanded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StreakTile(
                  group: group,
                  expanded: true,
                  onTap: () =>
                      setState(() => _expanded.remove(group.groupKey)),
                ),
                for (final entry in group.entries)
                  _EntryTile(
                    entry: entry,
                    dateFmt: dateFmt,
                    title: group.title,
                    nested: true,
                    onTap: () => _openEntry(entry),
                    onDelete: () => _deleteEntry(entry),
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
            onDelete: () => _deleteEntry(entry),
          );
        },
      ),
    );
  }
}

class _PickGameBottomSheet extends StatefulWidget {
  final List<CollectionItem> items;

  const _PickGameBottomSheet({required this.items});

  @override
  State<_PickGameBottomSheet> createState() => _PickGameBottomSheetState();
}

class _PickGameBottomSheetState extends State<_PickGameBottomSheet> {
  final _searchController = TextEditingController();
  List<Map<String, String>> _bggResults = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  List<CollectionItem> get _filteredCollection {
    final q = _query.toLowerCase();
    if (q.length < 2) return widget.items;
    return widget.items
        .where((i) => i.title.toLowerCase().contains(q))
        .toList();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _query;
    if (q.length < 2) {
      setState(() => _bggResults = []);
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), () => _searchBgg(q));
  }

  Future<void> _searchBgg(String q) async {
    setState(() => _searching = true);
    try {
      final r = await BggService.searchGames(q);
      if (mounted) setState(() => _bggResults = r);
    } catch (_) {
      if (mounted) setState(() => _bggResults = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = _filteredCollection;
    final showBgg = _query.length >= 2;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Pour quel jeu ?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Rechercher (collection ou BGG)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _bggResults = []);
                            },
                          ),
                  ),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      title: Text(
                        showBgg ? 'Ma collection' : 'Ma collection',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: showBgg && collection.isEmpty
                          ? const Text(
                              'Aucun jeu correspondant dans ta collection',
                              style: TextStyle(fontSize: 12),
                            )
                          : null,
                    ),
                    for (final item in collection)
                      ListTile(
                        leading: _historyThumb(item.imageUrl),
                        title: Text(item.title),
                        onTap: () => Navigator.pop(
                          context,
                          _GamePick.owned(item),
                        ),
                      ),
                    if (showBgg && _bggResults.isNotEmpty) ...[
                      const ListTile(
                        title: Text(
                          'Résultats BGG (jeu non possédé)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final g in _bggResults)
                        ListTile(
                          leading: _historyThumb(g['image_url']),
                          title: Text(g['title'] ?? 'Jeu'),
                          subtitle: const Text(
                            'Partie sans ajouter à la collection',
                            style: TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(
                            context,
                            _GamePick.bgg(
                              bggId: g['id'],
                              title: g['title'] ?? 'Jeu',
                              imageUrl: g['image_url'],
                            ),
                          ),
                        ),
                    ],
                    if (showBgg && !_searching && _bggResults.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Aucun résultat BGG pour « $_query ».',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
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
  final VoidCallback? onDelete;
  final String? imageUrl;
  final bool nested;

  const _EntryTile({
    required this.entry,
    required this.dateFmt,
    required this.title,
    required this.onTap,
    this.onDelete,
    this.imageUrl,
    this.nested = false,
  });

  @override
  Widget build(BuildContext context) {
    final session = entry.session;
    final scores = session.scoresLine;
    final winner = session.winnerLine;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.only(bottom: 8, left: nested ? 16 : 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!nested) ...[
                _historyThumb(imageUrl),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nested ? dateFmt.format(session.date) : title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (!nested) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateFmt.format(session.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (scores != null && scores.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        scores,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                    if (winner != null && winner.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        winner,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
