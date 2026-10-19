import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/boardgame_play_session.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/global_play_history_service.dart';
import '../services/play_share_service.dart';
import '../services/player_alias_service.dart';
import '../widgets/boardgame_play_history_panel.dart';
import '../widgets/boardgame_ranking_panel.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/empty_state_view.dart';
import '../utils/collection_pick_dedupe.dart';
import '../widgets/orphan_attach_sheet.dart';
import '../widgets/player_alias_linker_sheet.dart';
import 'shake_pick_screen.dart';

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
    PlayerAliasService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
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

  Future<CollectionItem> _itemForEntry(GlobalPlayHistoryEntry entry) async {
    if (entry.itemId != null) {
      final items = await _service.fetchBoardgameItems();
      return items.firstWhere(
        (i) => i.id == entry.itemId,
        orElse: () => _fallbackItem(entry),
      );
    }
    return _fallbackItem(entry);
  }

  Future<void> _openEntry(GlobalPlayHistoryEntry entry) async {
    final item = await _itemForEntry(entry);
    if (!mounted) return;
    final edited = await Navigator.push<BoardgamePlaySession>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgamePlaySessionPage(
          item: item,
          initial: entry.session,
        ),
        fullscreenDialog: true,
      ),
    );
    if (edited != null) {
      await _service.replaceSession(entry, edited);
      await _maybeShareSession(edited, entry);
    }
    if (mounted) _load();
  }

  Future<void> _relaunchEntry(GlobalPlayHistoryEntry entry) async {
    final item = await _itemForEntry(entry);
    if (!mounted) return;
    final session = await Navigator.push<BoardgamePlaySession>(
      context,
      MaterialPageRoute(
        builder: (_) => BoardgamePlaySessionPage(
          item: item,
          template: entry.session,
        ),
        fullscreenDialog: true,
      ),
    );
    if (session == null) return;

    if (entry.itemId != null) {
      final fresh = await _itemForEntry(entry);
      final sessions = parseBoardgamePlays(fresh.metadata);
      await _service.saveSessionToItem(fresh, [session, ...sessions]);
    } else {
      await _service.addOrphan(
        OrphanBoardgamePlay(
          id: 'orphan_${DateTime.now().microsecondsSinceEpoch}',
          title: entry.title,
          bggId: entry.bggId,
          imageUrl: entry.imageUrl,
          session: session,
        ),
      );
    }
    await _maybeShareSession(session, entry);
    if (mounted) _load();
  }

  Future<void> _attachOrphan(GlobalPlayHistoryEntry entry) async {
    final orphanId = entry.orphanId;
    if (orphanId == null) return;
    final items = rankOrphanAttachCandidates(
      await _service.fetchBoardgameItems(),
      orphanTitle: entry.title,
      orphanBggId: entry.bggId,
    );
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun jeu dans ta collection.')),
      );
      return;
    }
    final target = await showModalBottomSheet<CollectionItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => OrphanAttachSheet(
        orphanTitle: entry.title,
        candidates: items,
      ),
    );
    if (target == null || !mounted) return;
    final ok = await _service.attachOrphanToItem(
      orphanId: orphanId,
      item: target,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Partie rattachée à « ${target.title} »'
              : 'Partie introuvable (déjà rattachée ?)',
        ),
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
      await _maybeShareSession(
        session,
        GlobalPlayHistoryEntry(
          itemId: picked.item!.id,
          title: picked.item!.title,
          imageUrl: picked.item!.imageUrl,
          bggId: picked.item!.metadata?['bgg_id']?.toString(),
          session: session,
          sessionIndex: 0,
        ),
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
      await _maybeShareSession(
        session,
        GlobalPlayHistoryEntry(
          title: picked.title!,
          imageUrl: picked.imageUrl,
          bggId: picked.bggId,
          session: session,
          sessionIndex: 0,
          isOrphan: true,
        ),
      );
    }
    _load();
  }

  Future<void> _maybeShareSession(
    BoardgamePlaySession session,
    GlobalPlayHistoryEntry entry,
  ) async {
    await PlayShareService.instance.shareFinishedPlay(
      session: session,
      gameTitle: entry.title,
      bggId: entry.bggId,
      imageUrl: entry.imageUrl,
    );
  }

  Future<void> _openAliasLinker() async {
    await PlayerAliasService.instance.ensureLoaded();
    final names = <String>{};
    for (final e in _entries) {
      for (final p in e.session.players) {
        final t = p.trim();
        if (t.isNotEmpty) names.add(t);
      }
      final grid = e.session.scoreGrid;
      if (grid != null) {
        for (final n in grid.players) {
          final t = n.trim();
          if (t.isNotEmpty) names.add(t);
        }
      }
    }
    if (!mounted) return;
    var changed = false;
    await showPlayerAliasLinkerSheet(
      context,
      knownNames: names.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      onMutated: () => changed = true,
    );
    if (changed && mounted) await _load();
  }

  void _openDraw() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const ShakePickScreen(category: CollectionCategory.boardgame),
      ),
    );
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

    final topPlayed = [..._groups]
      ..sort((a, b) => b.entries.length.compareTo(a.entries.length));
    final wide = MediaQuery.sizeOf(context).width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des parties'),
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addSession,
              icon: const Icon(Icons.add_rounded, size: 26),
              label: const Text(
                'Nouvelle partie',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              extendedPadding: const EdgeInsets.symmetric(horizontal: 28),
            )
          : null,
      floatingActionButtonLocation: wide
          ? FloatingActionButtonLocation.centerFloat
          : FloatingActionButtonLocation.endFloat,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _GlobalPlayHistoryLayout(
              gameCount: _groups.length,
              playCount: allSessions.length,
              topPlayed: topPlayed
                  .take(5)
                  .map((g) => _PlayHistoryTopGame(g.title, g.entries.length))
                  .toList(),
              onOpenIdentities: _openAliasLinker,
              onOpenDraw: _openDraw,
              child: Column(
              children: [
                if (MediaQuery.sizeOf(context).width <= 1100)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _openDraw,
                        icon: const Icon(Icons.casino_outlined),
                        label: const Text('Tirage au sort'),
                      ),
                    ),
                  ),
                if (MediaQuery.sizeOf(context).width <= 1100)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openAliasLinker,
                        icon: const Icon(Icons.people_alt_outlined),
                        label: const Text('Identités joueurs'),
                      ),
                    ),
                  ),
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
            ),
    );
  }

  Widget _buildAllTimeRanking(List<BoardgamePlaySession> sessions) {
    if (sessions.isEmpty) {
      return EmptyStateView(
        icon: Icons.emoji_events_outlined,
        title: 'Aucune partie enregistrée',
        subtitle: 'Ajoute une partie depuis un jeu ou l\'historique global.',
        action: FilledButton.icon(
          onPressed: _addSession,
          icon: const Icon(Icons.add),
          label: const Text('Nouvelle partie'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Text(
            'Classement général',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          BoardgameRankingPanel(
            sessions: sessions,
            gameTitles: _entries.map((e) => e.title).toList(),
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
      return EmptyStateView(
        icon: Icons.history_edu_outlined,
        title: 'Historique vide',
        subtitle:
            'Tes parties apparaîtront ici — même pour les jeux que tu ne possèdes pas encore.',
        action: FilledButton.icon(
          onPressed: _addSession,
          icon: const Icon(Icons.add),
          label: const Text('Enregistrer une partie'),
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
          final expanded = _expanded.contains(group.streakKey);

          if (group.isStreak && !expanded) {
            return _StreakTile(
              group: group,
              onTap: () => setState(() => _expanded.add(group.streakKey)),
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
                      setState(() => _expanded.remove(group.streakKey)),
                ),
                for (final entry in group.entries)
                  _EntryTile(
                    entry: entry,
                    dateFmt: dateFmt,
                    title: group.title,
                    nested: true,
                    onTap: () => _openEntry(entry),
                    onRelaunch: () => _relaunchEntry(entry),
                    onAttach:
                        entry.isOrphan ? () => _attachOrphan(entry) : null,
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
            onRelaunch: () => _relaunchEntry(entry),
            onAttach: entry.isOrphan ? () => _attachOrphan(entry) : null,
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
    final base = q.length < 2
        ? widget.items
        : widget.items.where((i) => i.title.toLowerCase().contains(q));
    return dedupeCollectionItemsForPick(base);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _query;
    if (q.length < 2) {
      setState(() => _bggResults = []);
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 450), () => _searchBgg(q));
  }

  Future<void> _searchBgg(String q) async {
    setState(() => _searching = true);
    try {
      final r = await BggService.searchGames(q, lightweight: true);
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
                        key: ValueKey('pick-owned-${item.id}'),
                        leading: _historyThumb(
                          item.imageUrl,
                          size: _thumbSize(context),
                          key: ValueKey('pick-thumb-${item.id}'),
                        ),
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
                          key: ValueKey('pick-bgg-${g['id']}'),
                          leading: _historyThumb(
                            g['image_url']?.toString(),
                            key: ValueKey('pick-bgg-thumb-${g['id']}'),
                            size: _thumbSize(context),
                          ),
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

Widget _historyThumb(String? url, {Key? key, double size = 40}) {
  if (url == null || url.isEmpty) {
    return Icon(Icons.extension_outlined, key: key, size: size * 0.7);
  }
  return ClipRRect(
    key: key,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: size,
      height: size,
      child: BggNetworkImage(url: url, boxedCover: true, compact: true),
    ),
  );
}

double _thumbSize(BuildContext context) =>
    MediaQuery.sizeOf(context).width > 1100 ? 64 : 40;

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
        leading: _historyThumb(group.imageUrl, size: _thumbSize(context)),
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
  final VoidCallback? onRelaunch;
  final VoidCallback? onAttach;
  final VoidCallback? onDelete;
  final String? imageUrl;
  final bool nested;

  const _EntryTile({
    required this.entry,
    required this.dateFmt,
    required this.title,
    required this.onTap,
    this.onRelaunch,
    this.onAttach,
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _historyThumb(imageUrl, size: _thumbSize(context)),
                    if (session.isInProgress)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nested ? dateFmt.format(session.date) : title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (session.isInProgress)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'En cours',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                      ],
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
                    if (session.players.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final name in session.players)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.person_outline, size: 16),
                              label: Text(name),
                              onPressed: () => showPlayerAliasLinkerSheet(
                                context,
                                knownNames: [name],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onRelaunch != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: onRelaunch,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Partie'),
                  ),
                ),
              if (onAttach != null)
                IconButton(
                  key: const ValueKey('attach_orphan'),
                  icon: const Icon(Icons.link),
                  tooltip: 'Rattacher à un jeu de ma collection',
                  onPressed: onAttach,
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

class _PlayHistoryTopGame {
  final String title;
  final int plays;

  const _PlayHistoryTopGame(this.title, this.plays);
}

/// Contenu centré (max 950 px) + panneaux latéraux sur grand écran.
class _GlobalPlayHistoryLayout extends StatelessWidget {
  static const maxContentWidth = 950.0;

  final int gameCount;
  final int playCount;
  final List<_PlayHistoryTopGame> topPlayed;
  final VoidCallback onOpenIdentities;
  final VoidCallback onOpenDraw;
  final Widget child;

  const _GlobalPlayHistoryLayout({
    required this.gameCount,
    required this.playCount,
    required this.topPlayed,
    required this.onOpenIdentities,
    required this.onOpenDraw,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSide = constraints.maxWidth > 1100;
        final center = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: child,
        );

        if (!showSide) {
          return Align(alignment: Alignment.topCenter, child: center);
        }

        Widget statCard({
          required String title,
          required String value,
          required IconData icon,
          String? caption,
        }) {
          return Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (caption != null && caption.isNotEmpty)
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        Widget identitiesCard() {
          return Card(
            elevation: 0,
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            child: InkWell(
              onTap: onOpenIdentities,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.people_alt_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Identités joueurs',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget topPlayedCard() {
          if (topPlayed.isEmpty) return const SizedBox.shrink();
          return Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.emoji_events_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Top jeux joués',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < topPlayed.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            '#${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              topPlayed[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${topPlayed[i].plays}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 250,
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 56, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    statCard(
                      title: 'Parties enregistrées',
                      value: '$playCount',
                      icon: Icons.history_edu_outlined,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      color: scheme.secondaryContainer.withValues(alpha: 0.55),
                      child: InkWell(
                        onTap: onOpenDraw,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(Icons.casino_outlined, color: scheme.primary),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Tirage au sort',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    statCard(
                      title: 'Jeux distincts',
                      value: '$gameCount',
                      icon: Icons.extension_outlined,
                      caption: 'Historique global',
                    ),
                    const SizedBox(height: 12),
                    identitiesCard(),
                    const SizedBox(height: 12),
                    topPlayedCard(),
                  ],
                ),
              ),
                ),
              ),
            ),
            Flexible(child: center),
            const Expanded(child: SizedBox.shrink()),
          ],
        );
      },
    );
  }
}
