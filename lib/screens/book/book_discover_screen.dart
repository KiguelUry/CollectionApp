import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../coordinators/book_item_add_coordinator.dart';
import '../../models/book_series.dart';
import '../../models/book_subcategory.dart';
import '../../models/book_volume.dart';
import '../../services/anilist_manga_service.dart';
import '../../services/book_series_service.dart';
import '../../services/itunes_books_service.dart';
import '../../utils/book_series_normalizer.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/collection_cover_image.dart';
import '../book_series_detail_screen.dart';

/// Découvrir livres : prochaines sorties + tendances.
class BookDiscoverScreen extends StatefulWidget {
  final bool embedded;

  const BookDiscoverScreen({super.key, this.embedded = false});

  @override
  State<BookDiscoverScreen> createState() => _BookDiscoverScreenState();
}

class _BookDiscoverScreenState extends State<BookDiscoverScreen> {
  final _service = BookSeriesService();
  bool _loading = true;
  List<_UpcomingEntry> _upcoming = [];
  List<_TrendEntry> _trends = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final upcomingFut = _loadUpcoming();
      final trendsFut = _loadTrends();
      final upcoming = await upcomingFut;
      final trends = await trendsFut;
      if (!mounted) return;
      setState(() {
        _upcoming = upcoming;
        _trends = trends;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_UpcomingEntry>> _loadUpcoming() async {
    final bundle = await _service.fetchCollectionBundle();
    final out = <_UpcomingEntry>[];
    for (final series in bundle.series) {
      final volumes = bundle.volumesBySeries[series.id] ?? const [];
      for (final v in volumes) {
        if (!v.isUpcoming) continue;
        out.add(_UpcomingEntry(series: series, volume: v));
      }
    }
    out.sort((a, b) {
      final ad = a.volume.publishedDate;
      final bd = b.volume.publishedDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return out;
  }

  Future<List<_TrendEntry>> _loadTrends() async {
    final out = <_TrendEntry>[];
    final manga = await AnilistMangaService.trendingManga(limit: 10);
    for (final m in manga) {
      out.add(
        _TrendEntry(
          title: m.title,
          coverUrl: m.coverUrl,
          subtitle: m.author ?? 'Manga · Tendance AniList',
          rating: m.ratingOnFive,
          subcategory: BookSubcategory.manga,
          source: 'anilist',
        ),
      );
    }
    try {
      final apple = await ItunesBooksService.search(
        'bestseller roman français',
        limit: 12,
      );
      for (final h in apple.take(8)) {
        final title = (h['title'] ?? '').trim();
        if (title.isEmpty) continue;
        final name = BookSeriesNormalizer.displaySeriesName(title);
        if (out.any(
          (e) => BookSeriesNormalizer.namesMatch(e.title, name),
        )) {
          continue;
        }
        out.add(
          _TrendEntry(
            title: name,
            coverUrl: h['image_url'],
            subtitle: h['author'] ?? 'Roman · Apple Books',
            rating: null,
            subcategory: BookSubcategory.novel,
            source: 'apple',
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  Future<void> _openSeries(BookSeries series) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookSeriesDetailScreen(seriesId: series.id),
      ),
    );
  }

  Future<void> _addTrend(_TrendEntry t) async {
    await BookItemAddCoordinator(context).openSearch(
      subcategory: t.subcategory,
      initialQuery: t.title,
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = BookAccent.primary;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                const Text(
                  '📅 Prochaines sorties de mes séries',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (_upcoming.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('Aucune sortie planifiée pour l\'instant.'),
                  )
                else
                  ..._upcoming.map(_upcomingTile),
                const SizedBox(height: 16),
                const Text(
                  '🔥 Tendances Mangas / BD / Romans',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (_trends.isEmpty)
                  const Text('Tendances indisponibles pour le moment.')
                else
                  ..._trends.map(_trendTile),
              ],
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppAppBar(
        title: 'Découvrir',
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Recherche libre',
            icon: const Icon(Icons.search),
            onPressed: () => BookItemAddCoordinator(context).openSearch(),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _upcomingTile(_UpcomingEntry e) {
    final name = BookSeriesNormalizer.displaySeriesName(e.series.name);
    final cover = e.volume.coverUrl ?? e.series.coverUrl;
    final label = e.volume.upcomingLabel ?? 'À paraître';
    return Card(
      child: ListTile(
        onTap: () => _openSeries(e.series),
        leading: SizedBox(
          width: 44,
          height: 64,
          child: cover != null && cover.isNotEmpty
              ? CollectionCoverImage(
                  url: cover,
                  bookCover: true,
                  fit: BoxFit.cover,
                )
              : const ColoredBox(color: Color(0xFF4C1D95)),
        ),
        title: Text(
          '$name — Tome ${e.volume.displayNumber}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('⏳ $label'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _trendTile(_TrendEntry t) {
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 44,
          height: 64,
          child: t.coverUrl != null && t.coverUrl!.isNotEmpty
              ? CollectionCoverImage(
                  url: t.coverUrl!,
                  bookCover: true,
                  fit: BoxFit.cover,
                )
              : const ColoredBox(color: Color(0xFF334155)),
        ),
        title: Text(
          t.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          t.rating == null
              ? t.subtitle
              : '${t.subtitle} · ★ ${t.rating!.toStringAsFixed(1)}',
        ),
        trailing: FilledButton(
          onPressed: () => _addTrend(t),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('+ Ajouter'),
        ),
      ),
    );
  }
}

class _UpcomingEntry {
  final BookSeries series;
  final BookVolume volume;

  const _UpcomingEntry({required this.series, required this.volume});
}

class _TrendEntry {
  final String title;
  final String? coverUrl;
  final String subtitle;
  final double? rating;
  final BookSubcategory subcategory;
  final String source;

  const _TrendEntry({
    required this.title,
    required this.coverUrl,
    required this.subtitle,
    required this.rating,
    required this.subcategory,
    required this.source,
  });
}
