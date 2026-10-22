import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/boardgame_discover_seeds.dart';
import '../../models/bgg_catalog_game.dart';
import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../services/bgg_catalog_cache.dart';
import '../../services/bgg_service.dart';
import '../../services/user_boardgame_collection_service.dart';
import '../../utils/boardgame_genres.dart';
import '../../utils/collection_grid_layout.dart';
import '../../utils/boardgame_quick_add.dart';
import '../../utils/boardgame_bulk_add.dart';
import '../../utils/display_text.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/bgg_network_image.dart';

enum _DiscoverMode { forYou, recent, hot, upcoming, era, table }

typedef _Seed = DiscoverSeed;

/// Page Découvrir : cartes visuelles, notes BGG, ajout collection / wishlist.
class BoardgameDiscoverScreen extends StatefulWidget {
  final List<CollectionItem> owned;

  const BoardgameDiscoverScreen({super.key, this.owned = const []});

  @override
  State<BoardgameDiscoverScreen> createState() => _BoardgameDiscoverScreenState();
}

class _BoardgameDiscoverScreenState extends State<BoardgameDiscoverScreen> {
  /// Aligné sur le batch BGG (≤20 IDs / requête).
  static const _page = BggService.discoverThingBatchSize;

  late List<_Seed> _order;
  List<_Seed> _hot = [];
  List<_Seed> _upcoming = [];
  bool _hotLoading = false;
  bool _upcomingLoading = false;
  _DiscoverMode _mode = _DiscoverMode.forYou;
  int _eraFrom = 2015;
  int _eraTo = 2020;
  int? _tablePlayers;
  int? _maxMinutes;
  int _visible = _page;
  int _shuffleSalt = 0;
  /// Métadonnées indexées exclusivement par `bgg_id`.
  final _details = <String, Map<String, dynamic>>{};
  Set<String> _ownedKeys = {};
  Set<String> _wishlistKeys = {};
  final _inflightIds = <String>{};
  bool _firstPageReady = false;

  bool get _canShuffle =>
      _mode == _DiscoverMode.forYou ||
      _mode == _DiscoverMode.era ||
      _mode == _DiscoverMode.table;

  @override
  void initState() {
    super.initState();
    _order = _mix(widget.owned, salt: _shuffleSalt);
    unawaited(_purgeStaleDiscoverCache());
    unawaited(_loadMembership());
    // Premier écran d'abord (sans annuler via un compteur partagé).
    unawaited(_bootstrapFirstPage());
  }

  /// Purge SharedPreferences + mémoire des paires titre/image corrompues (v4).
  Future<void> _purgeStaleDiscoverCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in const [
        'discover_cache_v1',
        'discover_cache_v2',
        'discover_cache_v3',
      ]) {
        await prefs.remove(key);
      }
      const epoch = 'v4';
      if (prefs.getString(kDiscoverLocalCacheEpoch) != epoch) {
        BggCatalogCache.instance.clearMemory();
        await prefs.setString(kDiscoverLocalCacheEpoch, epoch);
      }
    } catch (_) {}
  }

  Future<void> _bootstrapFirstPage() async {
    // Tendances / sorties : Hot BGG dès l'ouverture (pas d'IDs hardcodés).
    await _ensureHot(force: false);
    await _hydrateUpTo(_visible + _page);
    if (mounted) setState(() => _firstPageReady = true);
  }

  Future<void> _hydrateIds(List<String> ids) async {
    final need = ids.where((id) {
      if (_inflightIds.contains(id)) return false;
      final d = _details[id];
      if (d == null) return true;
      final hasImage = (d['image_url']?.toString() ?? '').isNotEmpty;
      final hasTitle = (d['title']?.toString() ?? '').isNotEmpty;
      return !hasImage || !hasTitle;
    }).toList();
    if (need.isEmpty) return;

    // Un seul batch (≤20) = 1 SQL cache + au plus 1 appel bgg-api groupé.
    const width = BggService.discoverThingBatchSize;
    for (var i = 0; i < need.length; i += width) {
      if (!mounted) return;
      final slice = need.skip(i).take(width).toList();
      for (final id in slice) {
        _inflightIds.add(id);
      }
      try {
        final byId = await BggService.fetchThingDetailsByIds(slice);
        if (!mounted) return;
        setState(() {
          for (final id in slice) {
            final details = byId[id];
            if (details == null) continue;
            // Règle d'or : title / image / year / rating = payload BGG du bgg_id.
            _details[id] = {
              'bgg_id': id,
              'id': id,
              'title': details['title'],
              'image_url': details['image_url'],
              if (details['year_published'] != null)
                'year_published': details['year_published'],
              if (details['bgg_avg_rating'] != null)
                'bgg_avg_rating': details['bgg_avg_rating'],
              if (details['min_players'] != null)
                'min_players': details['min_players'],
              if (details['max_players'] != null)
                'max_players': details['max_players'],
              if (details['playing_time'] != null)
                'playing_time': details['playing_time'],
              if (details['bgg_description'] != null)
                'bgg_description': details['bgg_description'],
              if (details['bgg_gallery_urls'] != null)
                'bgg_gallery_urls': details['bgg_gallery_urls'],
            };
          }
        });
      } finally {
        for (final id in slice) {
          _inflightIds.remove(id);
        }
      }
    }
  }

  List<_Seed> _uniquePool() {
    final byId = <String, _Seed>{};
    for (final seed in kDiscoverPopularSeeds) {
      byId.putIfAbsent(seed.id, () => seed);
    }
    return byId.values.toList();
  }

  List<_Seed> _mix(List<CollectionItem> owned, {required int salt}) {
    final scores = <String, int>{};
    for (final item in owned) {
      if (item.isWishlist || item.isSold) continue;
      for (final g in boardgameGenresFromMetadata(item.metadata)) {
        scores[g] = (scores[g] ?? 0) + 1;
      }
    }
    final genres = scores.keys.toList();
    final pool = _uniquePool();
    final forYou = <_Seed>[];
    final rest = <_Seed>[];
    for (final seed in pool) {
      if (genres.isNotEmpty && seed.genres.any(genres.contains)) {
        forYou.add(seed);
      } else {
        rest.add(seed);
      }
    }
    final rnd = Random(DateTime.now().millisecondsSinceEpoch ^ salt);
    forYou.shuffle(rnd);
    rest.shuffle(rnd);
    final mixed = <_Seed>[];
    var i = 0;
    var j = 0;
    while (i < forYou.length || j < rest.length) {
      if (i < forYou.length) mixed.add(forYou[i++]);
      if (j < rest.length) mixed.add(rest[j++]);
      if (i < forYou.length && rnd.nextBool()) mixed.add(forYou[i++]);
    }
    return mixed;
  }

  Future<void> _loadMembership() async {
    try {
      final svc = UserBoardgameCollectionService();
      final owned = await svc.ownedCatalogKeys();
      final wish = await svc.wishlistCatalogKeys();
      if (!mounted) return;
      setState(() {
        _ownedKeys = owned;
        _wishlistKeys = wish;
      });
    } catch (_) {}
  }

  Future<void> _hydrateUpTo(int count) async {
    // Image exclusivement via bgg_id exact (/thing?id=) — jamais par index.
    final ids = _source.take(count).map((s) => s.id).toList();
    await _hydrateIds(ids);
  }

  void _showMore() {
    setState(() => _visible = (_visible + _page).clamp(0, _source.length));
    unawaited(_hydrateUpTo(_visible + _page));
  }

  void _reshuffle() {
    if (!_canShuffle) return;
    setState(() {
      _shuffleSalt++;
      _visible = _page;
      if (_mode == _DiscoverMode.forYou) {
        final hidden = _source.take(9).map((s) => s.id).toSet();
        final mixed = _mix(widget.owned, salt: _shuffleSalt);
        final fresh = mixed.where((s) => !hidden.contains(s.id)).toList();
        final rest = mixed.where((s) => hidden.contains(s.id)).toList();
        _order = [...fresh, ...rest];
      } else {
        // Era / table : nouveau tirage sur le vivier filtré.
        final rnd = Random(DateTime.now().millisecondsSinceEpoch ^ _shuffleSalt);
        final pool = List<_Seed>.from(_uniquePool())..shuffle(rnd);
        _order = pool;
      }
    });
    unawaited(_hydrateUpTo(_visible + _page));
  }

  String _cardMeta(_Seed seed) {
    final rating = _ratingLabel(_details[seed.id]?['bgg_avg_rating']);
    final year = _asInt(_details[seed.id]?['year_published']) ?? seed.yearHint;
    if (year == null) return rating;
    return '$rating · $year';
  }

  String _ratingLabel(Object? raw) {
    if (raw == null) return '…';
    final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (n == null) return '…';
    return '★ ${n.toStringAsFixed(1)}';
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse('$raw');
  }

  double? _asDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw');
  }

  List<_Seed> get _pool {
    final byId = <String, _Seed>{};
    for (final seed in [
      ..._order,
      ..._hot,
      ..._upcoming,
      ...kDiscoverUpcomingSeeds,
      ..._uniquePool(),
    ]) {
      byId[seed.id] = seed;
    }
    return byId.values.toList();
  }

  bool _isOwned(_Seed seed) =>
      _ownedKeys.contains(seed.id) ||
      _ownedKeys.contains('title:${seed.title.trim().toLowerCase()}');

  bool _matches(_Seed seed) {
    final d = _details[seed.id];
    final year = _asInt(d?['year_published']) ?? seed.yearHint;
    final rating = _asDouble(d?['bgg_avg_rating']);
    final minP = _asInt(d?['min_players']);
    final maxP = _asInt(d?['max_players']);
    final time = _asInt(d?['playing_time']);
    switch (_mode) {
      case _DiscoverMode.forYou:
        return true;
      case _DiscoverMode.hot:
        return _hot.any((s) => s.id == seed.id);
      case _DiscoverMode.recent:
        // Strict : uniquement 2025 et 2026 (jamais 2027+).
        if (year == null || (year != 2025 && year != 2026)) return false;
        if (rating != null && rating < 6.5) return false;
        return true;
      case _DiscoverMode.upcoming:
        // Année réelle BGG si connue, sinon yearHint du seed.
        if (year == null) return false;
        return year >= 2027;
      case _DiscoverMode.era:
        if (year == null) return false;
        return year >= _eraFrom && year <= _eraTo;
      case _DiscoverMode.table:
        // Sans détails BGG encore : garder le vivier visible pendant le hydrate.
        if (d == null) return _tablePlayers != null || _maxMinutes != null;
        if (_tablePlayers == 2) {
          if (minP == null || maxP == null || minP > 2 || maxP < 2) {
            return false;
          }
        } else if (_tablePlayers == 4) {
          if (minP == null || maxP == null || minP > 4 || maxP < 3) {
            return false;
          }
        } else if (_tablePlayers == 6) {
          if (maxP == null || maxP < 5) return false;
        }
        if (_maxMinutes != null) {
          if (time == null || time > _maxMinutes!) return false;
        }
        return _tablePlayers != null || _maxMinutes != null;
    }
  }

  List<_Seed> get _source {
    List<_Seed> list;
    if (_mode == _DiscoverMode.forYou) {
      list = List<_Seed>.from(_order);
    } else if (_mode == _DiscoverMode.hot) {
      // 100 % dynamique : uniquement /xmlapi2/hot (aucun seed hardcodé).
      list = List<_Seed>.from(_hot);
    } else if (_mode == _DiscoverMode.recent) {
      // Nouvelles sorties = Hot BGG années 2025|2026 uniquement.
      list = _hot.where(_matches).toList();
      list.sort((a, b) {
        final ay = _asInt(_details[a.id]?['year_published']) ?? a.yearHint ?? 0;
        final by = _asInt(_details[b.id]?['year_published']) ?? b.yearHint ?? 0;
        return by.compareTo(ay);
      });
    } else if (_mode == _DiscoverMode.upcoming) {
      // Dynamique (API upcoming) + Hot/pool filtrés year >= 2027.
      final byId = <String, _Seed>{};
      for (final s in [..._upcoming, ..._pool.where(_matches)]) {
        byId.putIfAbsent(s.id, () => s);
      }
      list = byId.values.where(_matches).toList();
      list.sort((a, b) {
        final ay = _asInt(_details[a.id]?['year_published']) ?? a.yearHint ?? 0;
        final by = _asInt(_details[b.id]?['year_published']) ?? b.yearHint ?? 0;
        return ay.compareTo(by);
      });
    } else {
      list = _pool.where(_matches).toList();
      list.sort((a, b) {
        final ar = _asDouble(_details[a.id]?['bgg_avg_rating']) ?? 0;
        final br = _asDouble(_details[b.id]?['bgg_avg_rating']) ?? 0;
        return br.compareTo(ar);
      });
    }
    // Possédés en fin de liste (grisés), non exclus pour garder du volume.
    final fresh = <_Seed>[];
    final owned = <_Seed>[];
    for (final s in list) {
      if (_isOwned(s)) {
        owned.add(s);
      } else {
        fresh.add(s);
      }
    }
    return [...fresh, ...owned];
  }

  void _ingestGameMaps(
    List<Map<String, String>> maps, {
    required void Function(List<_Seed> seeds) assign,
    bool markCrowdfunding = false,
  }) {
    final seeds = <_Seed>[];
    final ids = <String>[];
    for (final map in maps) {
      final id = map['id'] ?? map['bgg_id'] ?? '';
      final title = cleanDisplayText(map['title'] ?? '');
      if (id.isEmpty || title.isEmpty) continue;
      ids.add(id);
      final year = int.tryParse(map['year'] ?? '');
      final cf = markCrowdfunding ||
          map['crowdfunding'] == '1' ||
          map['crowdfunding'] == 'true' ||
          (year != null && year > DateTime.now().year);
      seeds.add(
        _Seed(id, title, const [], yearHint: year, crowdfunding: cf),
      );
      _details[id] = {
        'bgg_id': id,
        'id': id,
        'title': title,
        if ((map['image_url'] ?? '').isNotEmpty) 'image_url': map['image_url'],
        if (year != null) 'year_published': year,
        if (cf) 'crowdfunding': true,
        if (map['avg_rating'] != null)
          'bgg_avg_rating': double.tryParse(map['avg_rating']!),
        if (map['min_players'] != null)
          'min_players': int.tryParse(map['min_players']!),
        if (map['max_players'] != null)
          'max_players': int.tryParse(map['max_players']!),
        if (map['playing_time'] != null)
          'playing_time': int.tryParse(map['playing_time']!),
      };
    }
    assign(seeds);
    if (ids.isNotEmpty) {
      unawaited(_hydrateIds(ids.take(_page * 2).toList()));
    }
  }

  Future<void> _ensureHot({bool force = false}) async {
    if ((!force && _hot.isNotEmpty) || _hotLoading) return;
    setState(() => _hotLoading = true);
    try {
      final maps = await BggService.fetchHotBoardgames();
      if (!mounted) return;
      _ingestGameMaps(maps, assign: (seeds) => setState(() => _hot = seeds));
    } finally {
      if (mounted) setState(() => _hotLoading = false);
    }
  }

  Future<void> _ensureUpcoming({bool force = false}) async {
    if ((!force && _upcoming.isNotEmpty) || _upcomingLoading) return;
    setState(() => _upcomingLoading = true);
    try {
      final maps = await BggService.fetchUpcomingBoardgames();
      if (!mounted) return;
      _ingestGameMaps(
        maps,
        markCrowdfunding: true,
        assign: (seeds) => setState(() => _upcoming = seeds),
      );
      // Si l'API renvoie peu, hydrater aussi le vivier yearHint >= 2027.
      if (_upcoming.length < 20) {
        final extras = <String>[
          for (final s in [...kDiscoverUpcomingSeeds, ..._uniquePool()])
            if ((s.yearHint ?? 0) >= 2027) s.id,
        ];
        if (extras.isNotEmpty) await _hydrateIds(extras.take(30).toList());
      }
    } finally {
      if (mounted) setState(() => _upcomingLoading = false);
    }
  }

  void _selectMode(_DiscoverMode mode) {
    setState(() {
      _mode = mode;
      _visible = mode == _DiscoverMode.era
          ? 12
          : mode == _DiscoverMode.upcoming
              ? 24
              : _page;
    });
    if (mode == _DiscoverMode.hot || mode == _DiscoverMode.recent) {
      unawaited(_ensureHot());
    }
    if (mode == _DiscoverMode.upcoming) {
      unawaited(_ensureUpcoming());
    }
    unawaited(_hydrateUpTo(_visible + _page));
  }

  BggCatalogGame _game(_Seed seed) {
    // bgg_id = seule source de vérité dès que le cache/BGG a répondu.
    final d = _details[seed.id];
    final avg = d?['bgg_avg_rating'];
    final image = d?['image_url']?.toString().trim();
    final detailTitle = d?['title']?.toString().trim();
    // ÉCRASE toujours le titre seed dès qu'un titre BGG est disponible.
    final title = (detailTitle != null && detailTitle.isNotEmpty)
        ? detailTitle
        : seed.title;
    return BggCatalogGame(
      bggId: seed.id,
      title: cleanDisplayText(title),
      imageUrl: (image != null && image.isNotEmpty) ? image : null,
      subtitle: avg == null ? null : _ratingLabel(avg),
    );
  }

  bool _isCrowdfunding(_Seed seed) {
    if (seed.crowdfunding) return true;
    final d = _details[seed.id];
    if (d?['crowdfunding'] == true) return true;
    final year = _asInt(d?['year_published']) ?? seed.yearHint;
    return year != null && year > DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final shown = source.take(_visible).toList();
    final hasMore = _visible < source.length;

    return Scaffold(
      appBar: AppAppBar(
        title: 'Découvrir',
        showBackButton: true,
        actions: [
          if (_canShuffle)
            IconButton(
              tooltip: 'Nouvelles idées',
              onPressed: _reshuffle,
              icon: const Icon(Icons.casino_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Pour toi et les jeux du moment',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (!_firstPageReady)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _modeChip('Pour toi', _DiscoverMode.forYou),
                const SizedBox(width: 6),
                _modeChip('🔥 Sorties récentes au top', _DiscoverMode.recent),
                const SizedBox(width: 6),
                _modeChip('⏳ Prochaines sorties', _DiscoverMode.upcoming),
                const SizedBox(width: 6),
                _modeChip('📈 Tendances', _DiscoverMode.hot),
                const SizedBox(width: 6),
                _modeChip('🏆 Pépites par époque', _DiscoverMode.era),
                const SizedBox(width: 6),
                _modeChip('🎯 Pour ma table', _DiscoverMode.table),
              ],
            ),
          ),
          if (_mode == _DiscoverMode.era) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final range in const [
                  (2010, 2014),
                  (2015, 2020),
                  (2021, 2026),
                ])
                  ChoiceChip(
                    label: Text('${range.$1}–${range.$2}'),
                    selected: _eraFrom == range.$1 && _eraTo == range.$2,
                    onSelected: (_) {
                      setState(() {
                      _eraFrom = range.$1;
                      _eraTo = range.$2;
                      _visible = 12;
                      });
                      unawaited(_hydrateUpTo(_visible + _page));
                    },
                  ),
              ],
            ),
          ],
          if (_mode == _DiscoverMode.table) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final players in const [2, 4, 6])
                  ChoiceChip(
                    label: Text(players == 2
                        ? '2 joueurs'
                        : players == 4
                            ? '3–4 joueurs'
                            : '5+ joueurs'),
                    selected: _tablePlayers == players,
                    onSelected: (_) {
                      setState(() {
                        _tablePlayers =
                            _tablePlayers == players ? null : players;
                        _visible = _page;
                      });
                      unawaited(_hydrateUpTo(_visible + _page));
                    },
                  ),
                for (final minutes in const [30, 60, 120])
                  ChoiceChip(
                    label: Text('≤ $minutes min'),
                    selected: _maxMinutes == minutes,
                    onSelected: (_) {
                      setState(() {
                        _maxMinutes = _maxMinutes == minutes ? null : minutes;
                        _visible = _page;
                      });
                      unawaited(_hydrateUpTo(_visible + _page));
                    },
                  ),
              ],
            ),
          ],
          if (_hotLoading || _upcomingLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (!_hotLoading &&
              !_upcomingLoading &&
              shown.isEmpty &&
              _mode != _DiscoverMode.forYou)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Aucun jeu pour ce filtre. Les notes et les années se chargent depuis BoardGameGeek.',
              ),
            ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            clipBehavior: Clip.hardEdge,
            addAutomaticKeepAlives: false,
            itemCount: shown.length,
            gridDelegate: CollectionGridLayout.collectionDelegate(
              context,
              CollectionCategory.boardgame,
            ),
            itemBuilder: (context, index) {
              final seed = shown[index];
              final game = _game(seed);
              final key = game.catalogKey;
              return _DiscoverCard(
                key: ValueKey(game.bggId),
                game: game,
                rating: _cardMeta(seed),
                crowdfunding: _mode == _DiscoverMode.upcoming &&
                    _isCrowdfunding(seed),
                inCollection: _ownedKeys.contains(key),
                inWishlist: _wishlistKeys.contains(key),
                onOpen: () => _openPreview(game),
                onCollection: () => _addCollection(game),
                onWishlist: () => _toggleWish(game),
              );
            },
          ),
          if (hasMore && _visible < source.length)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: _showMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Voir plus'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openPreview(BggCatalogGame game, {bool defaultWishlist = false}) async {
    // Modale unifiée (même widget que Collection / Wishlist).
    await quickAddBoardgameFromCatalog(
      context,
      game: game,
      defaultWishlist: defaultWishlist,
    );
    await _loadMembership();
  }

  Widget _modeChip(String label, _DiscoverMode mode) {
    final selected = _mode == mode;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _selectMode(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addCollection(BggCatalogGame game) async {
    await _openPreview(game, defaultWishlist: false);
  }

  Future<void> _toggleWish(BggCatalogGame game) async {
    final key = game.catalogKey;
    final inWish = _wishlistKeys.contains(key);
    if (inWish) {
      final ok = await toggleBoardgameWishlist(
        context,
        game: game,
        currentlyInWishlist: true,
      );
      if (!mounted || !ok) return;
      setState(() => _wishlistKeys.remove(key));
      return;
    }
    await _openPreview(game, defaultWishlist: true);
  }
}

class _DiscoverCard extends StatelessWidget {
  final BggCatalogGame game;
  final Object? rating;
  final bool crowdfunding;
  final bool inCollection;
  final bool inWishlist;
  final VoidCallback onOpen;
  final VoidCallback onCollection;
  final VoidCallback onWishlist;

  const _DiscoverCard({
    super.key,
    required this.game,
    required this.rating,
    this.crowdfunding = false,
    required this.inCollection,
    required this.inWishlist,
    required this.onOpen,
    required this.onCollection,
    required this.onWishlist,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratingLabel = rating?.toString() ?? '…';
    return Opacity(
      opacity: inCollection ? 0.45 : 1,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: game.imageUrl == null || game.imageUrl!.isEmpty
                            ? ColoredBox(
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.casino_outlined,
                                  color: Colors.grey.shade500,
                                ),
                              )
                            : BggNetworkImage(
                                key: ValueKey(
                                  'discover-${game.bggId}-${game.imageUrl}',
                                ),
                                url: game.imageUrl!,
                                boxedCover: true,
                                compact: true,
                                fit: BoxFit.contain,
                              ),
                      ),
                      if (crowdfunding)
                        Positioned(
                          top: 4,
                          left: 4,
                          right: 4,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade700
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '🚀 À paraître',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cleanDisplayText(game.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
                Text(
                  ratingLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: inWishlist ? null : onWishlist,
                          child: Text(
                            inWishlist ? 'Wishlist' : '+ Wishlist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 10),
                          ),
                          onPressed: inCollection ? null : onCollection,
                          child: Text(
                            inCollection ? 'OK' : '+ Coll.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
