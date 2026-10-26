import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/book_accent.dart';
import '../../models/book_subcategory.dart';
import '../../services/anilist_manga_service.dart';
import '../../services/book_catalog_service.dart';
import '../../services/book_intelligence_service.dart';
import '../../services/book_search_history.dart';
import '../../services/book_series_service.dart';
import '../../services/itunes_books_service.dart';
import '../../services/mangadex_service.dart';
import '../../utils/book_series_normalizer.dart';
import '../../utils/book_vf_edition.dart';
import '../../utils/web_image_proxy.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/catalog/catalog_item_tile.dart';
import '../../widgets/ui/empty_state.dart';

/// Grille visuelle de recherche livres (Google Books + iTunes).
class BookCatalogGridScreen extends StatefulWidget {
  final BookSubcategory? initialSub;
  final String? initialQuery;
  final void Function(Map<String, String> book, BookSubcategory sub)?
      onBookSelected;
  final Future<void> Function(
    String seriesName,
    BookSubcategory sub, {
    int? volumeCount,
    Map<int, String>? coversByVolume,
    Map<int, String>? publishedDatesByVolume,
    String? author,
  })? onAddSeries;

  const BookCatalogGridScreen({
    super.key,
    this.initialSub,
    this.initialQuery,
    this.onBookSelected,
    this.onAddSeries,
  });

  @override
  State<BookCatalogGridScreen> createState() => _BookCatalogGridScreenState();
}

class _OwnedSeriesInfo {
  final String seriesId;
  final int owned;
  final int total;
  final Set<int> ownedVolumes;

  const _OwnedSeriesInfo({
    required this.seriesId,
    required this.owned,
    required this.total,
    required this.ownedVolumes,
  });
}

class _BookCatalogGridScreenState extends State<BookCatalogGridScreen> {
  static const _accent = BookAccent.primary;

  /// `null` = Tous (défaut).
  BookSubcategory? _sub;
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherController = TextEditingController();
  final _volumeController = TextEditingController();
  final _titleFocus = FocusNode();

  List<EnrichedBookHit> _hits = [];
  List<SeriesBannerCandidate> _banners = [];
  final Set<String> _addedSeriesKeys = {};
  final Map<String, _OwnedSeriesInfo> _ownedByKey = {};
  List<String> _recent = [];
  bool _loading = false;
  bool _searched = false;
  bool _showRecent = true;

  @override
  void initState() {
    super.initState();
    _sub = widget.initialSub; // null = Tous
    _titleFocus.addListener(() {
      if (_titleFocus.hasFocus && _titleController.text.trim().isEmpty) {
        setState(() => _showRecent = true);
      }
    });
    _loadRecent();
    _loadOwnedIndex();
    if (widget.initialQuery != null && widget.initialQuery!.length >= 2) {
      _titleController.text = widget.initialQuery!;
      _search();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _volumeController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final list = await BookSearchHistory.load();
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _loadOwnedIndex() async {
    try {
      final service = BookSeriesService();
      final bundle = await service.fetchCollectionBundle();
      final map = <String, _OwnedSeriesInfo>{};
      for (final series in bundle.series) {
        final volumes = bundle.volumesBySeries[series.id] ?? const [];
        final items = bundle.itemsBySeries[series.id] ?? const [];
        final stats = service.computeStats(
          series: series,
          volumes: volumes,
          items: items,
        );
        final ownedNums = <int>{};
        for (final item in items) {
          if (item.isWishlist || item.isSold) continue;
          for (final v in volumes) {
            if (v.id == item.volumeId) {
              ownedNums.add(v.volumeNumber.round());
            }
          }
        }
        map[BookSeriesNormalizer.mergeKey(series.name)] = _OwnedSeriesInfo(
          seriesId: series.id,
          owned: stats.ownedCount,
          total: stats.totalSlots,
          ownedVolumes: ownedNums,
        );
      }
      if (mounted) {
        setState(() {
          _ownedByKey
            ..clear()
            ..addAll(map);
        });
      }
    } catch (_) {}
  }

  BookSearchFilters get _filters => BookSearchFilters(
        titleQuery: _titleController.text,
        authorQuery: _authorController.text,
        publisherQuery: _publisherController.text,
      );

  BookSubcategory get _effectiveSub => _sub ?? BookSubcategory.other;

  int? get _volumeFilter {
    final fromField = int.tryParse(_volumeController.text.trim());
    if (fromField != null && fromField > 0) return fromField;
    return BookSeriesNormalizer.parseCatalogSearchQuery(
      _titleController.text,
    ).volumeNumber;
  }

  Future<void> _search() async {
    final filters = _filters;
    final rawTitle = filters.titleQuery.trim();
    final parsed = BookSeriesNormalizer.parseCatalogSearchQuery(rawTitle);
    final seriesQ = parsed.seriesQuery.trim().isNotEmpty
        ? parsed.seriesQuery.trim()
        : rawTitle;
    final volumeHint = _volumeFilter;
    final apiQuery = [
      seriesQ,
      if (volumeHint != null) 'Tome $volumeHint',
      filters.authorQuery.trim(),
    ].where((s) => s.isNotEmpty).join(' ');

    if (apiQuery.length < 2 && filters.publisherQuery.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saisis au moins 2 caractères (titre ou auteur).'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _searched = true;
      _showRecent = false;
    });

    final historyLabel = volumeHint != null && seriesQ.isNotEmpty
        ? '$seriesQ $volumeHint'
        : (rawTitle.isNotEmpty ? rawTitle : apiQuery);
    // ignore: unawaited_futures
    BookSearchHistory.add(historyLabel).then((list) {
      if (mounted) setState(() => _recent = list);
    });

    final searchFilters = BookSearchFilters(
      titleQuery: seriesQ,
      authorQuery: filters.authorQuery,
      publisherQuery: filters.publisherQuery,
    );

    // AniList + MangaDex EN PREMIER (volumes réels + covers, même si GB 429).
    final officialBanners = <SeriesBannerCandidate>[];
    MangaDexSeriesMeta? primaryMangaDex;
    if (seriesQ.length >= 2 &&
        (_sub == null || _sub == BookSubcategory.manga)) {
      try {
        final mdList = await MangaDexService.searchManga(
          seriesQ,
          authorHint: filters.authorQuery.trim().isEmpty
              ? null
              : filters.authorQuery.trim(),
          limit: 3,
        );
        if (mdList.isNotEmpty) primaryMangaDex = mdList.first;

        final aniResults =
            await AnilistMangaService.searchManga(seriesQ, limit: 3);

        // Fusionne AniList + MangaDex par titre normalisé.
        final byKey = <String, SeriesBannerCandidate>{};
        for (final md in mdList) {
          final key = BookSeriesNormalizer.mergeKey(md.title);
          final vols = md.volumesPublished ?? 0;
          byKey[key] = SeriesBannerCandidate(
            name: md.title,
            volumeCount: vols > 0 ? vols : 1,
            coversByVolume: Map<int, String>.from(md.coverByVolume),
            detectedSubcategory: BookSubcategory.manga,
            author: md.author,
            coverUrl: md.seriesCoverUrl ?? md.coverByVolume[1],
            fromAnilist: true,
          );
        }
        for (final ani in aniResults) {
          final key = BookSeriesNormalizer.mergeKey(ani.title);
          final existing = byKey[key];
          final mdVols = existing?.volumeCount ?? 0;
          final aniVols = ani.volumes ?? 0;
          final count = [aniVols, mdVols].reduce((a, b) => a > b ? a : b);
          final covers = <int, String>{
            ...?existing?.coversByVolume,
            if (ani.coverUrl != null && ani.coverUrl!.isNotEmpty)
              1: existing?.coversByVolume[1] ?? ani.coverUrl!,
          };
          byKey[key] = SeriesBannerCandidate(
            name: existing?.name ?? ani.title,
            volumeCount: count > 0 ? count : (existing?.volumeCount ?? 0),
            coversByVolume: covers,
            detectedSubcategory: BookSubcategory.manga,
            author: existing?.author ?? ani.author,
            coverUrl: existing?.coverUrl ?? ani.coverUrl ?? covers[1],
            fromAnilist: true,
          );
        }
        // Ne jamais afficher « 1 tomes » si on n'a aucune info réelle.
        for (final e in byKey.values) {
          if (e.volumeCount < 1 && e.coversByVolume.isEmpty) continue;
          officialBanners.add(
            SeriesBannerCandidate(
              name: e.name,
              volumeCount: e.volumeCount > 0
                  ? e.volumeCount
                  : (e.coversByVolume.keys.isEmpty
                      ? 0
                      : e.coversByVolume.keys.reduce((a, b) => a > b ? a : b)),
              coversByVolume: e.coversByVolume,
              detectedSubcategory: BookSubcategory.manga,
              author: e.author,
              coverUrl: e.coverUrl,
              fromAnilist: true,
            ),
          );
        }
      } catch (_) {}
    }

    // Google Books (+ iTunes natif seulement) — 1 requête (+ filet si vide).
    var raw = await BookCatalogService.searchBooks(
      apiQuery.length >= 2 ? apiQuery : filters.publisherQuery,
      subcategory: _effectiveSub,
      filters: searchFilters,
    );
    if (raw.isEmpty && seriesQ.length >= 2 && officialBanners.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      raw = await BookCatalogService.searchBooks(
        volumeHint != null ? '$seriesQ Tome $volumeHint' : seriesQ,
        subcategory: _effectiveSub,
        filters: searchFilters,
      );
    }

    final withPhotos = await BookCatalogService.enrichAuthorPhotos(raw);
    var enriched = BookIntelligenceService.enrichAndRank(
      withPhotos,
      subcategory: _effectiveSub,
      filters: searchFilters,
    );
    if (enriched.isEmpty && withPhotos.isNotEmpty) {
      enriched = BookIntelligenceService.sortByVolumeThenScore(
        BookIntelligenceService.dedupeBySeriesVolume(
          withPhotos
              .map(
                (h) => BookIntelligenceService.enrichSingle(h, _effectiveSub),
              )
              .toList(),
        ),
      );
    }

    // Série officielle exacte → filtre strict « Tomes reliés » (pas Crooked Kingdom).
    final primarySeries = officialBanners.isNotEmpty
        ? officialBanners.first.name
        : seriesQ;
    final hasExactOfficial = officialBanners.any(
      (b) =>
          BookSeriesNormalizer.normalizeKey(b.name) ==
              BookSeriesNormalizer.normalizeKey(seriesQ) ||
          BookSeriesNormalizer.hitBelongsToSeries(b.name, seriesQ) ||
          BookSeriesNormalizer.normalizeKey(b.name).startsWith(
                BookSeriesNormalizer.normalizeKey(seriesQ),
              ),
    );
    if (hasExactOfficial) {
      enriched = enriched.where((h) {
        final title = h.raw['title'] ?? h.displayTitle;
        return BookSeriesNormalizer.hitBelongsToSeries(title, primarySeries);
      }).toList();
    }

    // Purge pollution US « Vol. N » (VIZ) — collection 100 % VF.
    enriched = enriched.where((h) {
      final title = h.raw['title'] ?? h.displayTitle;
      return BookVfEdition.isFrenchEdition(
        title: title,
        language: h.raw['language'],
        source: h.raw['source'],
      );
    }).toList();

    // MangaDex = fill covers SEULEMENT sur tomes VF déjà connus (GB FR).
    // Ne crée JAMAIS de faux tomes JP (ex. T12) ni de faux « À paraître ».
    if (primaryMangaDex != null) {
      final md = primaryMangaDex;
      final frVols = <int>{
        for (final h in enriched)
          if (h.parsed.volumeNumber != null) h.parsed.volumeNumber!.round(),
      };

      // iTunes FR uniquement pour trous de cover/date sur volumes VF existants.
      final needItunes = <int>[
        for (final h in enriched)
          if (h.parsed.volumeNumber != null &&
              ((h.imageUrl == null || h.imageUrl!.isEmpty) ||
                  h.publishedDate == null))
            h.parsed.volumeNumber!.round(),
      ];
      final itunesByVol = needItunes.isEmpty
          ? const <int, Map<String, String>>{}
          : await ItunesBooksService.lookupFrenchVolumesBatch(
              md.title,
              needItunes,
            );

      for (var i = 0; i < enriched.length; i++) {
        final h = enriched[i];
        final n = h.parsed.volumeNumber?.round();
        if (n == null || !frVols.contains(n)) continue;
        final it = itunesByVol[n];
        final mdCover = md.coverByVolume[n];
        // Priorité : cover GB déjà présente → iTunes FR → MangaDex (proxy).
        String? cover = h.imageUrl;
        var source = h.raw['source'] ?? 'google_books';
        if (cover == null || cover.isEmpty) {
          if (it != null && (it['image_url'] ?? '').isNotEmpty) {
            cover = it['image_url'];
            source = 'itunes';
          } else if (mdCover != null && mdCover.trim().isNotEmpty) {
            cover = coverUrlForWeb(mdCover);
            source = 'mangadex';
          }
        }
        // Date VF : GB > iTunes FR (jamais date US / MD).
        final pub = h.publishedDate ??
            (it != null &&
                    BookVfEdition.isFrenchEdition(
                      title: it['title'] ?? '',
                      language: it['language'],
                      source: 'itunes',
                    )
                ? it['published_date']
                : null);
        if ((cover != null && cover.isNotEmpty && h.imageUrl != cover) ||
            (pub != null && pub.isNotEmpty && h.publishedDate != pub)) {
          final raw = Map<String, String>.from(h.raw);
          if (cover != null && cover.isNotEmpty) raw['image_url'] = cover;
          if (pub != null && pub.isNotEmpty) {
            raw['published_date'] = pub;
            raw['language'] = raw['language'] ?? 'fr';
          }
          raw['source'] = source;
          enriched[i] = EnrichedBookHit(
            raw: raw,
            parsed: h.parsed,
            displayTitle: h.displayTitle,
            author: h.author ?? it?['author'] ?? md.author,
            publisher: h.publisher,
            estimatedTotalVolumes: h.estimatedTotalVolumes,
            score: h.score,
            detectedSubcategory: BookSubcategory.manga,
          );
        }
      }

      // N'injecte un tome manquant QUE s'il a une fiche iTunes FR « Tome N ».
      if (volumeHint != null && !frVols.contains(volumeHint)) {
        final it = itunesByVol[volumeHint] ??
            await ItunesBooksService.lookupFrenchVolume(md.title, volumeHint);
        if (it != null &&
            BookVfEdition.isFrenchEdition(
              title: it['title'] ?? '',
              language: it['language'],
              source: 'itunes',
            ) &&
            RegExp(r'\btome\s*\d+', caseSensitive: false)
                .hasMatch(it['title'] ?? '')) {
          enriched.add(
            EnrichedBookHit(
              raw: {
                'title': it['title'] ?? '${md.title} - Tome $volumeHint',
                'series_title': md.title,
                'series_volume': '$volumeHint',
                if (md.author != null) 'author': md.author!,
                if ((it['image_url'] ?? '').isNotEmpty)
                  'image_url': it['image_url']!,
                if ((it['published_date'] ?? '').isNotEmpty)
                  'published_date': it['published_date']!,
                'source': 'itunes',
                'language': 'fr',
              },
              parsed: BookSeriesNormalizer.parse(
                it['title'] ?? '${md.title} - Tome $volumeHint',
              ),
              displayTitle:
                  it['title'] ?? '${md.title} - Tome $volumeHint',
              author: md.author ?? it['author'],
              score: 15000.0 - volumeHint,
              estimatedTotalVolumes: frVols.length,
              detectedSubcategory: BookSubcategory.manga,
            ),
          );
        }
      }

      enriched.sort((a, b) {
        final av = a.parsed.volumeNumber?.round() ?? 9999;
        final bv = b.parsed.volumeNumber?.round() ?? 9999;
        if (volumeHint != null) {
          final aHit = av == volumeHint ? 0 : 1;
          final bHit = bv == volumeHint ? 0 : 1;
          if (aHit != bHit) return aHit.compareTo(bHit);
        }
        return av.compareTo(bv);
      });
    }

    if (_sub != null) {
      enriched = enriched.where((h) {
        final det = h.detectedSubcategory ??
            BookSeriesNormalizer.detectSubcategory(
              seriesName: h.parsed.seriesName,
              title: h.displayTitle,
              publisher: h.publisher,
            );
        return det == null || det == _sub;
      }).toList();
    }

    var banners = BookIntelligenceService.extractSeriesBanners(
      enriched,
      query: seriesQ.isNotEmpty ? seriesQ : rawTitle,
      subcategory: _effectiveSub,
    );
    if (_sub != null) {
      banners = banners.where((b) {
        final det = b.detectedSubcategory ??
            BookSeriesNormalizer.detectSubcategory(seriesName: b.name);
        return det == null || det == _sub;
      }).toList();
    }

    // Officiel (AniList/MangaDex) en tête, puis écrasé par la grille VF.
    final officialMergeKeys = {
      for (final o in officialBanners) BookSeriesNormalizer.mergeKey(o.name),
    };
    final mergedBanners = <SeriesBannerCandidate>[];
    final seenKeys = <String>{};
    for (final b in [...officialBanners, ...banners]) {
      final mergeKey = BookSeriesNormalizer.mergeKey(b.name);
      final fromOfficial = b.fromAnilist || officialMergeKeys.contains(mergeKey);
      final det = fromOfficial
          ? BookSubcategory.manga
          : (b.detectedSubcategory ??
              BookSeriesNormalizer.detectSubcategory(seriesName: b.name) ??
              BookSubcategory.manga);
      final key = fromOfficial
          ? 'official|$mergeKey'
          : BookSeriesNormalizer.seriesSubcategoryKey(b.name, det);
      if (fromOfficial && seenKeys.contains('official|$mergeKey')) continue;
      if (!fromOfficial && officialMergeKeys.contains(mergeKey)) continue;
      if (!seenKeys.add(key)) continue;
      if (!b.fromAnilist && b.volumeCount < 1) continue;

      // Hits VF de la grille = source de vérité (covers, dates, max tome).
      final vf = vfCatalogFromHits(enriched, b.name);
      var count = b.volumeCount;
      final covers = Map<int, String>.from(b.coversByVolume);
      final dates = Map<int, String>.from(b.publishedDatesByVolume);

      if (vf.maxVol >= 1) {
        // Ne laisse PAS MangaDex ajouter un T12 JP si VF s'arrête à 11.
        count = vf.maxVol;
        for (final e in vf.covers.entries) {
          covers[e.key] = e.value;
        }
        covers.removeWhere((k, _) => k > vf.maxVol);
        for (final e in vf.dates.entries) {
          dates[e.key] = e.value;
        }
        dates.removeWhere((k, _) => k > vf.maxVol);
      } else {
        for (final o in officialBanners) {
          if (BookSeriesNormalizer.mergeKey(o.name) == mergeKey) {
            if (o.volumeCount > count) count = o.volumeCount;
          }
        }
      }
      if (count < 1) continue;

      // Miniature bannière = Tome 1 VF en priorité absolue.
      final t1Vf = covers[1];
      final coverUrl = (t1Vf != null &&
              t1Vf.isNotEmpty &&
              !t1Vf.contains('mangadex'))
          ? t1Vf
          : (t1Vf ?? b.coverUrl ?? covers[1]);

      mergedBanners.add(
        SeriesBannerCandidate(
          name: BookSeriesNormalizer.displaySeriesName(b.name),
          volumeCount: count,
          coversByVolume: covers,
          publishedDatesByVolume: dates,
          detectedSubcategory: det,
          author: b.author,
          coverUrl: coverUrl,
          fromAnilist: fromOfficial,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _hits = enriched;
      _banners = mergedBanners;
      _loading = false;
    });
  }

  Future<void> _addSeries(SeriesBannerCandidate banner) async {
    // AniList / MangaDex → toujours Manga.
    final preferred = banner.fromAnilist
        ? BookSubcategory.manga
        : (banner.detectedSubcategory ??
            BookSeriesNormalizer.detectSubcategory(seriesName: banner.name) ??
            _effectiveSub);
    final key = BookSeriesNormalizer.seriesSubcategoryKey(
      banner.name,
      preferred,
    );
    if (_addedSeriesKeys.contains(key)) return;

    final cb = widget.onAddSeries;
    if (cb != null) {
      await cb(
        banner.name,
        preferred,
        volumeCount: banner.volumeCount,
        coversByVolume: banner.coversByVolume,
        publishedDatesByVolume: banner.publishedDatesByVolume,
        author: banner.author,
      );
      if (!mounted) return;
      setState(() => _addedSeriesKeys.add(key));
      await _loadOwnedIndex();
      return;
    }
    _select(
      EnrichedBookHit(
        raw: {
          'title': banner.name,
          'series_title': banner.name,
          'estimated_volumes': '${banner.volumeCount}',
          if (banner.author != null) 'author': banner.author!,
          if (banner.coversByVolume[1] != null)
            'image_url': banner.coversByVolume[1]!,
          'volume_covers_json': banner.coversByVolume.entries
              .map((e) => '${e.key}:${e.value}')
              .join('|'),
          if (banner.publishedDatesByVolume.isNotEmpty)
            'volume_dates_json': banner.publishedDatesByVolume.entries
                .map((e) => '${e.key}:${e.value}')
                .join('|'),
        },
        parsed: BookSeriesNormalizer.parse(banner.name),
        displayTitle: banner.name,
        score: 999,
        estimatedTotalVolumes: banner.volumeCount,
        author: banner.author,
      ),
    );
  }

  void _select(EnrichedBookHit hit) {
    final callback = widget.onBookSelected;
    final sub = hit.detectedSubcategory ??
        BookSeriesNormalizer.detectSubcategory(
          seriesName: hit.parsed.seriesName,
          title: hit.displayTitle,
          publisher: hit.publisher,
        ) ??
        _effectiveSub;
    final raw = Map<String, String>.from(hit.raw);
    final seriesKey = BookSeriesNormalizer.mergeKey(
      hit.parsed.seriesName ?? hit.displayTitle,
    );
    SeriesBannerCandidate? banner;
    for (final b in _banners) {
      if (BookSeriesNormalizer.mergeKey(b.name) == seriesKey) {
        banner = b;
        break;
      }
    }
    // Toujours le total VF de la bannière (ex. 11), jamais seulement le tome X.
    final estimated = banner?.volumeCount ?? hit.estimatedTotalVolumes;
    if (estimated != null && estimated > 0) {
      raw['estimated_volumes'] = '$estimated';
    }
    final covers = banner?.coversByVolume;
    if (covers != null && covers.isNotEmpty) {
      raw['volume_covers_json'] =
          covers.entries.map((e) => '${e.key}:${e.value}').join('|');
      if ((raw['image_url'] ?? '').isEmpty && covers[1] != null) {
        raw['image_url'] = covers[1]!;
      }
    }
    final dates = banner?.publishedDatesByVolume;
    if (dates != null && dates.isNotEmpty) {
      raw['volume_dates_json'] =
          dates.entries.map((e) => '${e.key}:${e.value}').join('|');
    }
    if (callback != null) {
      callback(raw, sub);
      return;
    }
    Navigator.pop(context, (raw, sub));
  }

  String _subBadge(BookSubcategory? sub) {
    if (sub == null) return '';
    return switch (sub) {
      BookSubcategory.manga => '⛩️ Manga',
      BookSubcategory.comic => '💬 BD',
      BookSubcategory.comics => '🦸 Comics',
      BookSubcategory.novel => '📖 Roman',
      _ => sub.label,
    };
  }

  _OwnedSeriesInfo? _ownedFor(String name) =>
      _ownedByKey[BookSeriesNormalizer.mergeKey(name)];

  Widget _filterChip({
    required String label,
    String? emoji,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final fg = selected ? Colors.white : null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: emoji != null
            ? Text(emoji, style: TextStyle(color: fg, fontSize: 14))
            : null,
        label: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        selected: selected,
        selectedColor: _accent,
        checkmarkColor: Colors.white,
        showCheckmark: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.only(left: 2, right: 8),
        side: BorderSide(
          color: selected
              ? _accent
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildRecentPills() {
    if (_recent.isEmpty || !_showRecent || _titleController.text.trim().isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🕘 Recherches récentes',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in _recent.take(8))
                InputChip(
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _titleController.text = q;
                    final parsed =
                        BookSeriesNormalizer.parseCatalogSearchQuery(q);
                    if (parsed.volumeNumber != null) {
                      _volumeController.text = '${parsed.volumeNumber}';
                      _titleController.text = parsed.seriesQuery;
                    }
                    _search();
                  },
                  onDeleted: () async {
                    final list = await BookSearchHistory.remove(q);
                    if (mounted) setState(() => _recent = list);
                  },
                  deleteIconColor: Colors.grey,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      label: 'Tous',
                      selected: _sub == null,
                      onTap: () {
                        setState(() => _sub = null);
                        if (_searched) _search();
                      },
                    ),
                    for (final s in BookSubcategory.filterChips)
                      _filterChip(
                        label: s.label,
                        emoji: s.filterEmoji,
                        selected: _sub == s,
                        onTap: () {
                          setState(() => _sub = s);
                          if (_searched) _search();
                        },
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      focusNode: _titleFocus,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        if (v.trim().isEmpty) {
                          setState(() => _showRecent = true);
                        }
                      },
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: 'Rechercher un titre, une série...',
                        isDense: true,
                        prefixIcon: Icon(Icons.menu_book_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _search,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                  ),
                ],
              ),
            ),
            _buildRecentPills(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _authorController,
                      decoration: const InputDecoration(
                        hintText: 'Auteur',
                        isDense: true,
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _publisherController,
                      decoration: const InputDecoration(
                        hintText: 'Éditeur',
                        isDense: true,
                        prefixIcon: Icon(Icons.business_outlined, size: 20),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _volumeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        hintText: 'N° de tome',
                        isDense: true,
                        prefixIcon: Icon(Icons.tag, size: 20),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Text(
                'AniList + MangaDex + Google Books · couvertures HD',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHitSections() {
    final volumes = <EnrichedBookHit>[];
    final chapters = <EnrichedBookHit>[];
    for (final h in _hits) {
      final title = h.raw['title'] ?? h.displayTitle;
      if (BookSeriesNormalizer.looksLikeChapterOrScan(title)) {
        chapters.add(h);
      } else {
        volumes.add(h);
      }
    }
    return [
      if (volumes.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Tomes reliés (${volumes.length})',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        _hitsGrid(volumes, chapterBadge: false),
      ],
      if (chapters.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Chapitres / scans (${chapters.length})',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        _hitsGrid(chapters, chapterBadge: true),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  Widget _hitsGrid(List<EnrichedBookHit> hits, {required bool chapterBadge}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.62,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final hit = hits[index];
            final det = hit.detectedSubcategory;
            final seriesName = hit.parsed.seriesName ?? hit.displayTitle;
            final owned = _ownedFor(seriesName);
            final vol = hit.parsed.volumeNumber?.round();
            final alreadyOwned = !chapterBadge &&
                owned != null &&
                vol != null &&
                owned.ownedVolumes.contains(vol);
            return Stack(
              children: [
                CatalogItemTile(
                  name: hit.displayTitle,
                  subtitle: [
                    if (chapterBadge) '📄 Scan',
                    if (_sub == null && det != null) _subBadge(det),
                    if (hit.author != null && hit.author!.isNotEmpty)
                      hit.author!,
                    if (!chapterBadge && vol != null) 'Tome $vol',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  imageUrl: hit.imageUrl,
                  accent: chapterBadge
                      ? Colors.blueGrey
                      : (det ?? _effectiveSub).color,
                  aspectRatio: 0.62,
                  highQualityImage: true,
                  placeholderIcon: chapterBadge
                      ? Icons.article_outlined
                      : Icons.menu_book_outlined,
                  onTap: () => _select(hit),
                ),
                if (chapterBadge)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Chapitre',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (!chapterBadge && hit.isUpcoming)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7E57C2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        hit.upcomingLabel ?? '⏳ À paraître',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (alreadyOwned)
                  Positioned(
                    top: 4,
                    left: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26A69A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '✓ Dans ma collection',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
          childCount: hits.length,
        ),
      ),
    );
  }

  Widget _buildBanner(SeriesBannerCandidate banner) {
    final key = BookSeriesNormalizer.seriesSubcategoryKey(
      banner.name,
      banner.detectedSubcategory,
    );
    final added = _addedSeriesKeys.contains(key);
    final owned = _ownedFor(banner.name);
    final inCollection = owned != null && owned.owned > 0;
    final rawCover = banner.coverUrl ?? banner.coversByVolume[1];
    final cover =
        rawCover != null && rawCover.isNotEmpty ? coverUrlForWeb(rawCover) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: (added || inCollection) ? null : () => _addSeries(banner),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cover != null && cover.isNotEmpty
                      ? Image.network(
                          cover,
                          width: 44,
                          height: 62,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 44,
                            height: 62,
                            child: Center(
                              child: Text('📚', style: TextStyle(fontSize: 22)),
                            ),
                          ),
                        )
                      : const SizedBox(
                          width: 44,
                          height: 62,
                          child: Center(
                            child: Text('📚', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Série : ${banner.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        [
                          if (banner.detectedSubcategory != null)
                            _subBadge(banner.detectedSubcategory),
                          if (banner.author != null &&
                              banner.author!.trim().isNotEmpty)
                            banner.author!,
                          '${banner.volumeCount} tomes parus',
                          if (inCollection)
                            '✓ Dans ma collection (${owned.owned}/${owned.total})'
                          else if (added)
                            'Déjà dans ta collection'
                          else
                            'Ajouter la série',
                        ].where((s) => s.isNotEmpty).join(' — '),
                        style: TextStyle(
                          fontSize: 12,
                          color: inCollection
                              ? const Color(0xFF26A69A)
                              : Colors.grey.shade400,
                          fontWeight:
                              inCollection ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: (added || inCollection)
                      ? null
                      : () => _addSeries(banner),
                  child: Text(
                    inCollection || added ? '✓ Ajouté' : 'Ajouter',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppAppBar(
        title: 'Recherche livres',
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _buildFilters()),
          if (!_searched)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.auto_stories_outlined,
                title: 'Catalogue visuel',
                message:
                    'Ex. « Kingdom 2 », « One Piece », auteur « Hara »…',
                iconColor: _accent,
              ),
            )
          else if (_loading && _hits.isEmpty && _banners.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hits.isEmpty && _banners.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'Aucun résultat',
                message: 'Affine titre, auteur, éditeur ou n° de tome.',
                iconColor: _effectiveSub.color,
              ),
            )
          else ...[
            if (_banners.isNotEmpty)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      children: [
                        for (final b in _banners) _buildBanner(b),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ..._buildHitSections(),
          ],
        ],
      ),
    );
  }
}
