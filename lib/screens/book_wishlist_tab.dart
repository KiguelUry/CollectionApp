import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../models/book_series.dart';
import '../models/book_volume.dart';
import '../models/collection_item.dart';
import '../services/book_series_service.dart';
import '../utils/book_series_normalizer.dart';
import '../widgets/book_series_tile.dart';
import '../widgets/collection_cover_image.dart';
import 'book_series_detail_screen.dart';

/// Wishlist livres : séries entières + électrons libres (tomes précis).
class BookWishlistTab extends StatefulWidget {
  const BookWishlistTab({super.key});

  @override
  State<BookWishlistTab> createState() => _BookWishlistTabState();
}

class _BookWishlistTabState extends State<BookWishlistTab> {
  final _service = BookSeriesService();
  bool _loading = true;
  List<_WishSeries> _series = [];
  List<_FreeElectron> _electrons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bundle = await _service.fetchCollectionBundle();
      final seriesOut = <_WishSeries>[];
      final electrons = <_FreeElectron>[];
      for (final series in bundle.series) {
        final volumes = bundle.volumesBySeries[series.id] ?? const [];
        final items = bundle.itemsBySeries[series.id] ?? const [];
        final stats = _service.computeStats(
          series: series,
          volumes: volumes,
          items: items,
        );
        final wishItems =
            items.where((i) => i.isWishlist && !i.isSold).toList();
        final ownedCount = items
            .where((i) => !i.isWishlist && !i.isSold)
            .length;
        if (wishItems.isEmpty && !series.wishlistEntireSeries) continue;

        if (series.wishlistEntireSeries ||
            (ownedCount == 0 && wishItems.isNotEmpty)) {
          seriesOut.add(_WishSeries(series: series, stats: stats));
        }

        if (ownedCount > 0) {
          for (final item in wishItems) {
            BookVolume? vol;
            for (final v in volumes) {
              if (v.id == item.volumeId) {
                vol = v;
                break;
              }
            }
            if (vol == null) continue;
            electrons.add(
              _FreeElectron(series: series, volume: vol, item: item),
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _series = seriesOut;
        _electrons = electrons;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buyElectron(_FreeElectron e) async {
    final slot = BookVolumeSlot(
      volume: e.volume,
      item: e.item,
      status: BookVolumeStatus.wishlist,
    );
    await _service.toggleVolumeOwned(
      series: e.series,
      slot: slot,
      owned: true,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_series.isEmpty && _electrons.isEmpty) {
      return const Center(child: Text('Wishlist vide'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: BookAccent.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        children: [
          if (_series.isNotEmpty) ...[
            const Text(
              'Séries en wishlist',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _series.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.62,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (ctx, i) {
                final e = _series[i];
                return BookSeriesTile(
                  series: e.series,
                  stats: e.stats,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BookSeriesDetailScreen(seriesId: e.series.id),
                      ),
                    );
                    if (mounted) _load();
                  },
                );
              },
            ),
          ],
          if (_electrons.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Électrons libres',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Tomes précis à acheter dans des séries déjà commencées',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final e in _electrons)
              Card(
                child: ListTile(
                  leading: SizedBox(
                    width: 40,
                    height: 58,
                    child: e.volume.coverUrl != null
                        ? CollectionCoverImage(
                            url: e.volume.coverUrl!,
                            bookCover: true,
                            fit: BoxFit.cover,
                          )
                        : const ColoredBox(color: Color(0xFFA855F7)),
                  ),
                  title: Text(
                    '${BookSeriesNormalizer.displaySeriesName(e.series.name)} — Tome ${e.volume.displayNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('♡ Wishlist'),
                  trailing: FilledButton(
                    onPressed: () => _buyElectron(e),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF10B981),
                    ),
                    child: const Text('✓ Acheté'),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BookSeriesDetailScreen(seriesId: e.series.id),
                      ),
                    );
                    if (mounted) _load();
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _WishSeries {
  final BookSeries series;
  final BookSeriesStats stats;
  const _WishSeries({required this.series, required this.stats});
}

class _FreeElectron {
  final BookSeries series;
  final BookVolume volume;
  final CollectionItem item;
  const _FreeElectron({
    required this.series,
    required this.volume,
    required this.item,
  });
}
