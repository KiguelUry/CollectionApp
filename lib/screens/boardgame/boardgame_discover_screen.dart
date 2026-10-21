import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/bgg_catalog_game.dart';
import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../services/bgg_service.dart';
import '../../services/user_boardgame_collection_service.dart';
import '../../utils/boardgame_genres.dart';
import '../../utils/collection_grid_layout.dart';
import '../../utils/boardgame_quick_add.dart';
import '../../utils/boardgame_bulk_add.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/bgg_network_image.dart';

enum _DiscoverMode { forYou, recent, hot, upcoming, era, table }

class _Seed {
  final String id;
  final String title;
  final List<String> genres;
  final int? yearHint;
  const _Seed(this.id, this.title, this.genres, {this.yearHint});
}

/// Vivier élargi (classiques + pépites + sorties) pour éviter toujours les mêmes 10.
const _popular = <_Seed>[
  _Seed('224517', 'Brass: Birmingham', ['Strategy', 'Economic'], yearHint: 2018),
  _Seed('174430', 'Gloomhaven', ['Strategy', 'Adventure', 'Fantasy'], yearHint: 2017),
  _Seed('167791', 'Terraforming Mars', ['Strategy', 'Economic', 'Science Fiction'], yearHint: 2016),
  _Seed('342942', 'Ark Nova', ['Strategy'], yearHint: 2021),
  _Seed('266192', 'Wingspan', ['Strategy', 'Card Game'], yearHint: 2019),
  _Seed('169786', 'Scythe', ['Strategy', 'Economic'], yearHint: 2016),
  _Seed('161936', 'Pandemic Legacy: Season 1', ['Cooperative', 'Strategy'], yearHint: 2015),
  _Seed('13', 'Catan', ['Family', 'Strategy'], yearHint: 1995),
  _Seed('9209', 'Ticket to Ride', ['Family'], yearHint: 2004),
  _Seed('68448', '7 Wonders', ['Card Game', 'Strategy'], yearHint: 2010),
  _Seed('178900', 'Codenames', ['Party', 'Deduction'], yearHint: 2015),
  _Seed('822', 'Carcassonne', ['Family'], yearHint: 2000),
  _Seed('39856', 'Dixit', ['Party'], yearHint: 2008),
  _Seed('188920', 'Azul', ['Abstract', 'Family'], yearHint: 2017),
  _Seed('266524', 'PARKS', ['Family'], yearHint: 2019),
  _Seed('31260', 'Agricola', ['Economic', 'Strategy'], yearHint: 2007),
  _Seed('173346', '7 Wonders Duel', ['Card Game', 'Strategy'], yearHint: 2015),
  _Seed('148228', 'Splendor', ['Card Game', 'Family'], yearHint: 2014),
  _Seed('124361', 'Concordia', ['Strategy', 'Economic'], yearHint: 2013),
  _Seed('205637', 'Arkham Horror: The Card Game', ['Card Game', 'Adventure'], yearHint: 2016),
  _Seed('162886', 'Spirit Island', ['Strategy', 'Cooperative'], yearHint: 2017),
  _Seed('120677', 'Terra Mystica', ['Strategy', 'Economic'], yearHint: 2012),
  _Seed('182028', 'Through the Ages: A New Story of Civilization', ['Strategy', 'Economic'], yearHint: 2015),
  _Seed('291457', 'Gloomhaven: Jaws of the Lion', ['Strategy', 'Adventure'], yearHint: 2020),
  _Seed('35677', 'Le Havre', ['Economic', 'Strategy'], yearHint: 2008),
  _Seed('72125', 'Eclipse', ['Strategy', 'Science Fiction'], yearHint: 2011),
  _Seed('2651', 'Power Grid', ['Economic', 'Strategy'], yearHint: 2004),
  _Seed('3076', 'Puerto Rico', ['Economic', 'Strategy'], yearHint: 2002),
  _Seed('237182', 'Root', ['Strategy'], yearHint: 2018),
  _Seed('295947', 'Cascadia', ['Family'], yearHint: 2021),
  _Seed('316554', 'Dune: Imperium', ['Strategy', 'Card Game'], yearHint: 2020),
  _Seed('286849', 'The Crew: The Quest for Planet Nine', ['Card Game', 'Cooperative'], yearHint: 2019),
  _Seed('244521', 'The Quacks of Quedlinburg', ['Family'], yearHint: 2018),
  _Seed('233078', 'Twilight Imperium: Fourth Edition', ['Strategy'], yearHint: 2017),
  _Seed('199561', 'Sagrada', ['Family', 'Abstract'], yearHint: 2017),
  _Seed('230802', 'Azul: Stained Glass of Sintra', ['Abstract', 'Family'], yearHint: 2018),
  _Seed('266810', 'Paladins of the West Kingdom', ['Strategy'], yearHint: 2019),
  _Seed('193738', 'Great Western Trail', ['Strategy', 'Economic'], yearHint: 2016),
  _Seed('312484', 'Lost Ruins of Arnak', ['Strategy', 'Adventure'], yearHint: 2020),
  _Seed('284083', 'The Search for Planet X', ['Deduction'], yearHint: 2020),
  _Seed('341169', 'Heat: Pedal to the Metal', ['Racing', 'Family'], yearHint: 2022),
  _Seed('367220', 'Sky Team', ['Cooperative', 'Family'], yearHint: 2023),
  _Seed('359871', 'Harmonies', ['Family'], yearHint: 2024),
  _Seed('366013', 'Forest Shuffle', ['Card Game', 'Family'], yearHint: 2023),
  _Seed('283155', 'London (Second Edition)', ['Economic', 'Strategy'], yearHint: 2017),
  _Seed('163412', 'Patchwork', ['Abstract', 'Family'], yearHint: 2014),
  _Seed('170216', 'Blood Rage', ['Strategy', 'Fantasy'], yearHint: 2015),
  _Seed('187645', 'Star Wars: Rebellion', ['Strategy'], yearHint: 2016),
  _Seed('164153', 'Star Wars: Imperial Assault', ['Adventure', 'Miniatures'], yearHint: 2014),
  _Seed('209418', 'Dominion (Second Edition)', ['Card Game'], yearHint: 2016),
  _Seed('12333', 'Twilight Struggle', ['Strategy', 'Wargame'], yearHint: 2005),
  _Seed('70323', 'King of Tokyo', ['Family', 'Dice'], yearHint: 2011),
  _Seed('30549', 'Pandemic', ['Cooperative', 'Family'], yearHint: 2008),
  _Seed('54043', 'Jaipur', ['Card Game', 'Family'], yearHint: 2009),
  _Seed('129622', 'Love Letter', ['Card Game', 'Party'], yearHint: 2012),
  _Seed('172386', 'Mysterium', ['Party', 'Deduction'], yearHint: 2015),
  _Seed('181304', 'One Night Ultimate Werewolf', ['Party'], yearHint: 2014),
  _Seed('217372', 'The Mind', ['Party', 'Cooperative'], yearHint: 2017),
  _Seed('254188', 'Mind MGMT', ['Deduction', 'Strategy'], yearHint: 2021),
  // Sorties / annonces récentes (ids BGG exacts — image via /thing?id= uniquement).
  _Seed('420433', 'Final Girl: Frightmare on Maple Lane', ['Cooperative'], yearHint: 2025),
  _Seed('420546', 'Vantage', ['Adventure', 'Exploration'], yearHint: 2025),
  _Seed('367521', 'Bomb Busters', ['Deduction', 'Family'], yearHint: 2025),
  _Seed('416851', 'Finspan', ['Family'], yearHint: 2025),
  _Seed('436189', 'Fromage', ['Strategy'], yearHint: 2025),
  _Seed('413245', 'Seti: Search for Extraterrestrial Intelligence', ['Strategy'], yearHint: 2025),
  _Seed('428097', 'Keep the Heroes Out!', ['Cooperative'], yearHint: 2025),
  _Seed('428530', 'The Elder Scrolls: Betrayal of the Second Era', ['Adventure'], yearHint: 2025),
  _Seed('421236', 'Seas of Strife', ['Strategy'], yearHint: 2026),
  _Seed('439422', 'Captain Flip', ['Family'], yearHint: 2026),
  // Prochaines sorties (2027+) — exclus des « Sorties récentes ».
  _Seed('451852', 'Arcs: The Blighted Reach', ['Strategy'], yearHint: 2027),
  _Seed('444378', 'Windmill Valley', ['Family'], yearHint: 2027),
  _Seed('436127', 'Nucleum: Australia', ['Strategy'], yearHint: 2027),
  _Seed('440563', 'Endeavor: Deep Sea', ['Strategy'], yearHint: 2027),
  _Seed('328871', 'Terraforming Mars: Ares Expedition', ['Card Game', 'Strategy'], yearHint: 2021),
  _Seed('350184', 'Earth', ['Strategy'], yearHint: 2023),
  _Seed('342640', 'Marvel Champions: The Card Game', ['Card Game', 'Cooperative'], yearHint: 2019),
  _Seed('251247', 'Barrage', ['Strategy', 'Economic'], yearHint: 2019),
  _Seed('256916', 'Concordia Venus', ['Strategy', 'Economic'], yearHint: 2018),
  _Seed('177736', 'A Feast for Odin', ['Strategy', 'Economic'], yearHint: 2016),
  _Seed('199792', 'Everdell', ['Strategy', 'Family'], yearHint: 2018),
  _Seed('285774', 'Marvel United', ['Cooperative', 'Family'], yearHint: 2020),
  _Seed('299659', 'Wonderland\'s War', ['Strategy'], yearHint: 2022),
  _Seed('325494', 'Cascadia Junior', ['Family'], yearHint: 2024),
  _Seed('366906', 'Apiary', ['Strategy'], yearHint: 2023),
  _Seed('295486', 'My City', ['Family'], yearHint: 2020),
  _Seed('28143', 'Race for the Galaxy', ['Card Game', 'Strategy'], yearHint: 2007),
  _Seed('2655', 'Hive', ['Abstract'], yearHint: 2001),
  _Seed('41', 'Can\'t Stop', ['Family', 'Dice'], yearHint: 1980),
  _Seed('93', 'El Grande', ['Strategy'], yearHint: 1995),
  _Seed('215', 'Tigris & Euphrates', ['Strategy'], yearHint: 1997),
  _Seed('478', 'Ra', ['Strategy'], yearHint: 1999),
  _Seed('265236', 'Gaia Project', ['Strategy'], yearHint: 2017),
  _Seed('28720', 'Brass', ['Strategy', 'Economic'], yearHint: 2007),
  _Seed('110327', 'Lords of Waterdeep', ['Strategy'], yearHint: 2012),
  _Seed('62219', 'Dominant Species', ['Strategy'], yearHint: 2010),
  _Seed('123260', 'Village', ['Strategy'], yearHint: 2011),
  _Seed('150376', 'Dead of Winter', ['Strategy'], yearHint: 2014),
  _Seed('147020', 'Star Realms', ['Card Game'], yearHint: 2014),
  _Seed('131357', 'Coup', ['Party', 'Deduction'], yearHint: 2012),
  _Seed('70919', 'Takenoko', ['Family'], yearHint: 2011),
  _Seed('126163', 'Hanabi', ['Cooperative'], yearHint: 2010),
  _Seed('148228', 'Splendor', ['Family', 'Card Game'], yearHint: 2014),
  _Seed('159675', 'Dead Man\'s Draw', ['Card Game'], yearHint: 2014),
  _Seed('155821', 'Five Tribes', ['Strategy'], yearHint: 2014),
  _Seed('147949', 'One Night Ultimate Werewolf', ['Party'], yearHint: 2014),
  _Seed('128882', 'The Resistance: Avalon', ['Party', 'Deduction'], yearHint: 2012),
  _Seed('128621', 'Seasons', ['Card Game', 'Strategy'], yearHint: 2012),
  _Seed('113924', 'Zombicide', ['Adventure'], yearHint: 2012),
  _Seed('103343', 'A Few Acres of Snow', ['Strategy'], yearHint: 2011),
  _Seed('91514', '7 Wonders: Leaders', ['Card Game'], yearHint: 2011),
];

/// Page Découvrir : cartes visuelles, notes BGG, ajout collection / wishlist.
class BoardgameDiscoverScreen extends StatefulWidget {
  final List<CollectionItem> owned;

  const BoardgameDiscoverScreen({super.key, this.owned = const []});

  @override
  State<BoardgameDiscoverScreen> createState() => _BoardgameDiscoverScreenState();
}

class _BoardgameDiscoverScreenState extends State<BoardgameDiscoverScreen> {
  static const _page = 27;

  late List<_Seed> _order;
  List<_Seed> _hot = [];
  bool _hotLoading = false;
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

  @override
  void initState() {
    super.initState();
    _order = _mix(widget.owned, salt: _shuffleSalt);
    unawaited(_loadMembership());
    // Premier écran d'abord (sans annuler via un compteur partagé).
    unawaited(_bootstrapFirstPage());
  }

  Future<void> _bootstrapFirstPage() async {
    await _hydrateUpTo(_visible + _page);
    if (mounted) setState(() => _firstPageReady = true);
    unawaited(_prefetchUpcomingSeeds());
  }

  Iterable<_Seed> get _upcomingSeedCandidates => _uniquePool().where((s) {
        final y = s.yearHint;
        return y != null && y >= 2027;
      });

  Future<void> _prefetchUpcomingSeeds() async {
    final ids = _upcomingSeedCandidates.map((s) => s.id).toList();
    if (ids.isEmpty) return;
    await _hydrateIds(ids);
  }

  Future<void> _hydrateIds(List<String> ids) async {
    final need = ids.where((id) {
      if (_inflightIds.contains(id)) return false;
      final d = _details[id];
      if (d == null) return true;
      return (d['image_url']?.toString() ?? '').isEmpty;
    }).toList();
    if (need.isEmpty) return;
    const width = 6;
    for (var i = 0; i < need.length; i += width) {
      if (!mounted) return;
      final slice = need.skip(i).take(width).toList();
      for (final id in slice) {
        _inflightIds.add(id);
      }
      await Future.wait(slice.map((id) async {
        try {
          final details = await BggService.getGameFullDetails(id);
          if (details == null || !mounted) return;
          final returned = details['bgg_id']?.toString().trim();
          if (returned != null && returned.isNotEmpty && returned != id) {
            return;
          }
          final image = details['image_url']?.toString() ?? '';
          setState(() {
            _details[id] = {
              ...details,
              'bgg_id': id,
              if (image.isNotEmpty) 'image_url': image,
            };
          });
        } finally {
          _inflightIds.remove(id);
        }
      }));
    }
  }

  List<_Seed> _uniquePool() {
    final byId = <String, _Seed>{};
    for (final seed in _popular) {
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
    final hidden = _source.take(9).map((s) => s.id).toSet();
    setState(() {
      _shuffleSalt++;
      _mode = _DiscoverMode.forYou;
      final mixed = _mix(widget.owned, salt: _shuffleSalt);
      final fresh = mixed.where((s) => !hidden.contains(s.id)).toList();
      final rest = mixed.where((s) => hidden.contains(s.id)).toList();
      _order = [...fresh, ...rest];
      _visible = _page;
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
    for (final seed in [..._order, ..._hot, ..._uniquePool()]) {
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
        // Exclusion mutuelle avec « Prochaines sorties ».
        if (year == null || (year != 2025 && year != 2026)) return false;
        if (rating != null && rating < 6.8) return false;
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
      list = List<_Seed>.from(_hot);
    } else if (_mode == _DiscoverMode.upcoming) {
      list = _pool.where(_matches).toList();
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

  Future<void> _ensureHot() async {
    if (_hot.isNotEmpty || _hotLoading) return;
    setState(() => _hotLoading = true);
    try {
      final maps = await BggService.fetchHotBoardgames();
      if (!mounted) return;
      final seeds = <_Seed>[];
      for (final map in maps) {
        final id = map['id'] ?? map['bgg_id'] ?? '';
        final title = map['title'] ?? '';
        if (id.isEmpty || title.isEmpty) continue;
        seeds.add(_Seed(id, title, const []));
        // Pas d'image depuis le hot-list : uniquement via getGameFullDetails(bgg_id).
        _details[id] = {
          ...?_details[id],
          'bgg_id': id,
          if (map['year'] != null) 'year_published': int.tryParse(map['year']!),
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
      // Complète avec le vivier pour atteindre 20+ même si l'API renvoie peu.
      if (seeds.length < 24) {
        for (final seed in _uniquePool()) {
          if (seeds.any((s) => s.id == seed.id)) continue;
          seeds.add(seed);
          if (seeds.length >= 36) break;
        }
      }
      setState(() => _hot = seeds);
      unawaited(_hydrateUpTo(_visible + _page));
    } finally {
      if (mounted) setState(() => _hotLoading = false);
    }
  }

  void _selectMode(_DiscoverMode mode) {
    setState(() {
      _mode = mode;
      _visible = mode == _DiscoverMode.era ? 12 : _page;
    });
    if (mode != _DiscoverMode.forYou) unawaited(_ensureHot());
    if (mode == _DiscoverMode.upcoming) {
      unawaited(_prefetchUpcomingSeeds());
    }
    unawaited(_hydrateUpTo(_visible + _page));
  }

  BggCatalogGame _game(_Seed seed) {
    // Une seule source : _details[seed.id] (jamais un autre index).
    final d = _details[seed.id];
    final avg = d?['bgg_avg_rating'];
    final image = d?['image_url']?.toString().trim();
    final detailTitle = d?['title']?.toString().trim();
    // Tant que les détails ne sont pas là, titre seed ; image seulement si liée.
    final title = (detailTitle != null && detailTitle.isNotEmpty)
        ? detailTitle
        : seed.title;
    return BggCatalogGame(
      bggId: seed.id,
      title: title,
      imageUrl: (image != null && image.isNotEmpty) ? image : null,
      subtitle: avg == null ? null : _ratingLabel(avg),
    );
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
                const SizedBox(width: 6),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.casino, size: 18),
                  label: const Text('Nouvelles idées'),
                  onPressed: _reshuffle,
                ),
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
          if (_hotLoading) const LinearProgressIndicator(minHeight: 2),
          if (!_hotLoading && shown.isEmpty && _mode != _DiscoverMode.forYou)
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
  final bool inCollection;
  final bool inWishlist;
  final VoidCallback onOpen;
  final VoidCallback onCollection;
  final VoidCallback onWishlist;

  const _DiscoverCard({
    super.key,
    required this.game,
    required this.rating,
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
                  child: ClipRRect(
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
                ),
                const SizedBox(height: 4),
                Text(
                  game.title,
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
