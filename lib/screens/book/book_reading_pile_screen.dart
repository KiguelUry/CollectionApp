import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_series.dart';
import '../../models/book_volume.dart';
import '../../services/book_series_service.dart';
import '../../utils/book_series_normalizer.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/collection_cover_image.dart';
import '../book_series_detail_screen.dart';

/// Pile à lire + chasseur de trous (Sprint 2).
class BookReadingPileScreen extends StatefulWidget {
  const BookReadingPileScreen({super.key});

  @override
  State<BookReadingPileScreen> createState() => _BookReadingPileScreenState();
}

class _BookReadingPileScreenState extends State<BookReadingPileScreen>
    with SingleTickerProviderStateMixin {
  final _service = BookSeriesService();
  late final TabController _tabs;
  bool _loading = true;
  List<_PalEntry> _toRead = [];
  List<_HoleEntry> _holes = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bundle = await _service.fetchCollectionBundle();
      final toRead = <_PalEntry>[];
      final holes = <_HoleEntry>[];
      for (final series in bundle.series) {
        final volumes = bundle.volumesBySeries[series.id] ?? const [];
        final items = bundle.itemsBySeries[series.id] ?? const [];
        final stats = _service.computeStats(
          series: series,
          volumes: volumes,
          items: items,
        );
        if (stats.nextOwnedUnread != null) {
          final n = stats.nextOwnedUnread!;
          BookVolume? vol;
          for (final v in volumes) {
            if (!v.isHorsSerie && v.volumeNumber.round() == n) {
              vol = v;
              break;
            }
          }
          toRead.add(_PalEntry(series: series, volumeNumber: n, volume: vol));
        }
        if (stats.holeCount > 0) {
          final ownedNums = <int>{};
          final byVolId = {
            for (final i in items)
              if (i.volumeId != null && !i.isWishlist && !i.isSold)
                i.volumeId!: i,
          };
          for (final v in volumes) {
            if (v.isHorsSerie) continue;
            if (byVolId.containsKey(v.id)) {
              ownedNums.add(v.volumeNumber.round());
            }
          }
          if (ownedNums.isNotEmpty) {
            final maxOwned = ownedNums.reduce((a, b) => a > b ? a : b);
            for (var n = 1; n < maxOwned; n++) {
              if (ownedNums.contains(n)) continue;
              BookVolume? vol;
              for (final v in volumes) {
                if (!v.isHorsSerie && v.volumeNumber.round() == n) {
                  vol = v;
                  break;
                }
              }
              holes.add(_HoleEntry(series: series, volumeNumber: n, volume: vol));
            }
          }
        }
      }
      toRead.sort(
        (a, b) => a.series.name.toLowerCase().compareTo(b.series.name.toLowerCase()),
      );
      holes.sort(
        (a, b) => a.series.name.toLowerCase().compareTo(b.series.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _toRead = toRead;
        _holes = holes;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(_PalEntry e) async {
    await _service.markVolumesRead(
      series: e.series,
      fromVolume: e.volumeNumber,
      toVolume: e.volumeNumber,
    );
    await _load();
  }

  Future<void> _markOwned(_HoleEntry e) async {
    await _service.markVolumesOwned(
      series: e.series,
      fromVolume: e.volumeNumber,
      toVolume: e.volumeNumber,
    );
    await _load();
  }

  Future<void> _openSeries(BookSeries series) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookSeriesDetailScreen(seriesId: series.id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = BookAccent.primary;
    return Scaffold(
      appBar: AppAppBar(
        title: 'Pile à lire',
        backgroundColor: accent,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: '📖 À lire (${_toRead.length})'),
            Tab(text: '🧩 Trous (${_holes.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildToRead(),
                _buildHoles(),
              ],
            ),
    );
  }

  Widget _buildToRead() {
    if (_toRead.isEmpty) {
      return const Center(
        child: Text('Aucun tome possédé non lu. Bravo !'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        itemCount: _toRead.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final e = _toRead[i];
          final name = BookSeriesNormalizer.displaySeriesName(e.series.name);
          final cover = e.volume?.coverUrl ?? e.series.coverUrl;
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
                    : const ColoredBox(color: Color(0xFF334155)),
              ),
              title: Text(
                '$name — Tome ${e.volumeNumber} à lire',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(e.series.subcategory.label),
              trailing: FilledButton(
                onPressed: () => _markRead(e),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text('✓ T.${e.volumeNumber} lu'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHoles() {
    if (_holes.isEmpty) {
      return const Center(
        child: Text('Aucun trou dans tes collections. Nickel !'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        itemCount: _holes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final e = _holes[i];
          final name = BookSeriesNormalizer.displaySeriesName(e.series.name);
          final cover = e.volume?.coverUrl ?? e.series.coverUrl;
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
                    : const ColoredBox(color: Color(0xFF334155)),
              ),
              title: Text(
                '$name — Tome ${e.volumeNumber} manquant',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Trou avant ton dernier tome possédé'),
              trailing: OutlinedButton(
                onPressed: () => _markOwned(e),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('+ J\'ai trouvé'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PalEntry {
  final BookSeries series;
  final int volumeNumber;
  final BookVolume? volume;

  const _PalEntry({
    required this.series,
    required this.volumeNumber,
    this.volume,
  });
}

class _HoleEntry {
  final BookSeries series;
  final int volumeNumber;
  final BookVolume? volume;

  const _HoleEntry({
    required this.series,
    required this.volumeNumber,
    this.volume,
  });
}
