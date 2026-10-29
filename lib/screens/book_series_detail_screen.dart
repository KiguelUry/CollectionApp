import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../constants/rating_colors.dart';
import '../coordinators/book_item_add_coordinator.dart';
import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/book_volume.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/book_series_service.dart';
import '../utils/book_vf_edition.dart';
import '../services/books_collection_cache.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/book_manual_volume_dialog.dart';
import '../widgets/collection_cover_image.dart';
import '../widgets/precision_star_rating_bar.dart';

enum _VolumeFilter { all, owned, missing, toRead, wishlist }

/// Dossier série — frise hybride + grille de couvertures.
class BookSeriesDetailScreen extends StatefulWidget {
  final String seriesId;

  const BookSeriesDetailScreen({super.key, required this.seriesId});

  @override
  State<BookSeriesDetailScreen> createState() => _BookSeriesDetailScreenState();
}

class _BookSeriesDetailScreenState extends State<BookSeriesDetailScreen> {
  final _service = BookSeriesService();
  final _scroll = ScrollController();
  final _slotKeys = <String, GlobalKey>{};
  bool _loading = true;
  BookSeries? _series;
  BookSeriesStats? _stats;
  List<BookVolumeSlot> _slots = [];
  _VolumeFilter _filter = _VolumeFilter.all;
  bool _friseExpanded = false;
  int _synopsisPage = 0;
  bool _synopsisVisible = true;
  bool _chaptersExpanded = false;
  bool _refreshingPubs = false;
  /// `enrichMissingVolumeCovers` : une seule fois par ouverture d’écran.
  bool _hasEnrichedThisSession = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      var series = await _service.fetchSeriesById(widget.seriesId);
      if (series == null) throw Exception('Série introuvable');
      // Reloads silencieux : lecture seule (sinon enrich → PATCH → _load infini).
      if (!silent) {
        series = await _service.sanitizeSeriesName(series);
        await _service.dedupeVolumeItems(series.id);
        // Pas de Google Books ici : seulement AniList/MangaDex pour reclasser.
        series = await _service.reclassifyAsMangaIfConfirmed(series);
      }
      final volumes = await _service.fetchVolumes(series.id);
      final items = await _service.fetchSeriesItems(series.id);
      final stats = _service.computeStats(
        series: series,
        volumes: volumes,
        items: items,
      );
      final slots = _service.buildVolumeSlots(
        series: series,
        volumes: volumes,
        items: items,
      );
      BooksCollectionCache.instance.updateSeries(
        seriesId: series.id,
        series: series,
        volumes: volumes,
        items: items,
        stats: stats,
      );
      if (!mounted) return;
      setState(() {
        _series = series;
        _stats = stats;
        _slots = slots;
        _loading = false;
      });
      if (_hasEnrichedThisSession) return;
      _hasEnrichedThisSession = true;
      final seriesForBg = series;
      final volumesForBg = volumes;
      Future(() async {
        var any = false;
        if (seriesForBg.communityRating == null) {
          final hydrated =
              await _service.hydrateCommunityRating(seriesForBg);
          if (hydrated.communityRating != null) any = true;
        }
        final n = await _service.enrichMissingVolumeCovers(
          series: seriesForBg,
          volumes: volumesForBg,
          repairUnverified: true,
        );
        if (n > 0) any = true;
        if (any && mounted) await _load(silent: true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _refreshPublications() async {
    if (_series == null || _refreshingPubs) return;
    setState(() => _refreshingPubs = true);
    try {
      await _service.refreshPublications(_series!);
      if (mounted) await _load(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parutions actualisées')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingPubs = false);
    }
  }

  /// Frise : 1 clic = bascule Possédé ↔ Manquant.
  Future<void> _onFriseTap(BookVolumeSlot slot) async {
    await _toggleOwned(slot);
  }

  BookVolumeSlot _liveSlot(BookVolumeSlot slot) {
    for (final s in _slots) {
      if (s.volume.id == slot.volume.id) return s;
    }
    return slot;
  }

  /// Carte couverture : ouvre le détail en bottom sheet (pas en bas de page).
  Future<void> _onCardTap(BookVolumeSlot slot) async {
    final accent = BookAccent.primary;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) {
              return StatefulBuilder(
                builder: (modalCtx, setModal) {
                  final live = _liveSlot(slot);
                  return ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    children: [
                      _buildVolumeDrawer(
                        live,
                        accent,
                        inSheet: true,
                        onSheetChanged: () => setModal(() {}),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
    if (mounted) await _load(silent: true);
  }

  String _seriesStatsLine(BookSeriesStats stats) {
    final total = stats.totalSlots > 0 ? stats.totalSlots : _slots.length;
    final base =
        'Possédés : ${stats.ownedCount}/$total · Lus : ${stats.readCount}/$total';
    final upcoming = _slots.where((s) => s.volume.isUpcoming).length;
    final up = upcoming > 0 ? ' · $upcoming à paraître' : '';
    return '$base$up';
  }

  double? _slotRating(BookVolumeSlot slot) {
    if (!_slotRead(slot)) return null;
    final raw = _slotOwned(slot)
        ? slot.item?.rating
        : slot.volume.metadata['personal_rating'];
    if (raw == null) return null;
    final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (n == null || n < 0) return null;
    final onFive = n > 5.0 ? n / 2 : n;
    if (onFive < 0 || onFive > 5) return null;
    return double.parse(onFive.toStringAsFixed(1));
  }

  Future<void> _toggleWishlist(BookVolumeSlot slot) async {
    final next = !_slotWish(slot);
    try {
      await _service.toggleVolumeWishlist(
        series: _series!,
        slot: slot,
        wishlist: next,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  bool _slotOwned(BookVolumeSlot s) =>
      s.item != null && !s.item!.isWishlist;

  bool _slotRead(BookVolumeSlot s) =>
      (s.item?.isRead ?? false) || s.volume.isRead;

  bool _slotWish(BookVolumeSlot s) => s.item?.isWishlist == true;

  List<BookVolumeSlot> get _displaySlots {
    final copy = _slots.where((slot) {
      final owned = _slotOwned(slot);
      final wish = _slotWish(slot);
      final read = _slotRead(slot);
      return switch (_filter) {
        _VolumeFilter.all => true,
        _VolumeFilter.owned => owned,
        _VolumeFilter.missing => !owned && !wish,
        _VolumeFilter.toRead => owned && !read,
        _VolumeFilter.wishlist => wish,
      };
    }).toList()
      ..sort((a, b) => a.volume.sortIndex.compareTo(b.volume.sortIndex));
    return copy;
  }

  /// Tomes reliés physiques (frise + grille principale).
  List<BookVolumeSlot> get _physicalSlots =>
      _displaySlots.where((s) => !s.volume.isChapterOrScan).toList();

  /// Chapitres / scans en ligne (section séparée).
  List<BookVolumeSlot> get _chapterSlots =>
      _displaySlots.where((s) => s.volume.isChapterOrScan).toList();

  int _countFilter(_VolumeFilter f) {
    return _slots.where((slot) {
      final owned = _slotOwned(slot);
      final wish = _slotWish(slot);
      final read = _slotRead(slot);
      return switch (f) {
        _VolumeFilter.all => true,
        _VolumeFilter.owned => owned,
        _VolumeFilter.missing => !owned && !wish,
        _VolumeFilter.toRead => owned && !read,
        _VolumeFilter.wishlist => wish,
      };
    }).length;
  }

  /// Optimistic : met à jour le slot local immédiatement (0 ms).
  void _patchSlotLocal(
    BookVolumeSlot slot, {
    bool? owned,
    bool? read,
    bool? wishlist,
    BookVolumeEdition? edition,
    String? editionLanguage,
    double? rating,
    bool applyRating = false,
    bool clearRating = false,
  }) {
    final idx = _slots.indexWhere((s) => s.volume.id == slot.volume.id);
    if (idx < 0) return;
    final cur = _slots[idx];
    final nextOwned = owned ?? _slotOwned(cur);
    var nextRead = read ?? _slotRead(cur);
    if (applyRating && rating != null) nextRead = true;
    if (read == false) clearRating = true;
    final nextWish = wishlist ?? _slotWish(cur);

    var nextVolume = cur.volume;
    if (read != null || (applyRating && rating != null)) {
      nextVolume = nextVolume.copyWithMetadata({'is_read': nextRead});
    }
    if (clearRating) {
      nextVolume = nextVolume.copyWithMetadata({'personal_rating': null});
    } else if (applyRating && !nextOwned) {
      nextVolume = nextVolume.copyWithMetadata({'personal_rating': rating});
    }
    if (edition != null) {
      nextVolume = nextVolume.copyWithMetadata({'edition': edition.dbValue});
    }
    if (editionLanguage != null) {
      nextVolume =
          nextVolume.copyWithMetadata({'edition_language': editionLanguage});
    }

    CollectionItem? nextItem;
    if (!nextOwned && !nextWish && rating == null) {
      // Lu sans possession : flag volume uniquement.
      nextItem = null;
    } else {
      nextItem = _fakeItem(cur, wishlist: nextWish, read: nextRead);
      if (clearRating) {
        nextItem = nextItem.copyWith(clearRating: true);
      } else if (applyRating) {
        nextItem = nextItem.copyWith(rating: rating, isRead: nextRead);
      }
    }

    final status = nextWish
        ? BookVolumeStatus.wishlist
        : (nextOwned || (rating != null && nextItem != null)
            ? BookVolumeStatus.owned
            : BookVolumeStatus.missing);

    setState(() {
      _slots = List.of(_slots);
      _slots[idx] = BookVolumeSlot(
        volume: nextVolume,
        item: nextItem,
        status: status,
      );
      _stats = _service.computeStats(
        series: _series!,
        volumes: _slots.map((s) => s.volume).toList(),
        items: _slots.map((s) => s.item).whereType<CollectionItem>().toList(),
      );
    });
  }

  CollectionItem _fakeItem(
    BookVolumeSlot cur, {
    required bool wishlist,
    required bool read,
  }) {
    final existing = cur.item;
    if (existing != null && !existing.id.startsWith('local-')) {
      return CollectionItem(
        id: existing.id,
        title: existing.title,
        category: existing.category,
        subcategory: existing.subcategory,
        seriesId: existing.seriesId,
        volumeId: existing.volumeId ?? cur.volume.id,
        isWishlist: wishlist,
        isRead: read,
        quantity: existing.quantity,
        addedBy: existing.addedBy,
        locationUserId: existing.locationUserId,
        metadata: existing.metadata,
        imageUrl: existing.imageUrl,
        rating: existing.rating,
        purchasePrice: existing.purchasePrice,
        isSold: existing.isSold,
      );
    }
    return CollectionItem(
      id: 'local-${cur.volume.id}',
      title: '${_series!.name} - Tome ${cur.volume.displayNumber}',
      category: CollectionCategory.book,
      subcategory: _series!.subcategory.dbValue,
      seriesId: _series!.id,
      volumeId: cur.volume.id,
      isWishlist: wishlist,
      isRead: read,
      quantity: 1,
      addedBy: '',
    );
  }

  Future<void> _toggleOwned(BookVolumeSlot slot) async {
    final next = !_slotOwned(slot);
    _patchSlotLocal(slot, owned: next, wishlist: false);
    try {
      await _service.toggleVolumeOwned(
        series: _series!,
        slot: slot,
        owned: next,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
        await _load(silent: true);
      }
    }
  }

  Future<void> _toggleRead(BookVolumeSlot slot) async {
    // Lu possible sans possession (scan / en ligne).
    final next = !_slotRead(slot);
    _patchSlotLocal(slot, read: next);
    try {
      final refreshed = _slots.firstWhere((s) => s.volume.id == slot.volume.id);
      await _service.toggleVolumeRead(slot: refreshed, read: next);
    } catch (e) {
      if (mounted) await _load(silent: true);
    }
  }

  Future<void> _setEditionLanguage(BookVolumeSlot slot, String language) async {
    _patchSlotLocal(slot, editionLanguage: language);
    try {
      await _service.setVolumeEditionLanguage(
        volumeId: slot.volume.id,
        language: language,
      );
    } catch (e) {
      if (mounted) await _load(silent: true);
    }
  }

  Future<void> _setEdition(BookVolumeSlot slot, BookVolumeEdition edition) async {
    _patchSlotLocal(slot, edition: edition);
    try {
      await _service.setVolumeEdition(
        volumeId: slot.volume.id,
        edition: edition,
      );
    } catch (e) {
      if (mounted) await _load(silent: true);
    }
  }

  Future<void> _markRangeOwned() async {
    final series = _series!;
    final fromCtrl = TextEditingController(text: '1');
    final toCtrl = TextEditingController(
      text: '${series.expectedVolumeCount ?? _slots.length}',
    );
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cocher une plage'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fromCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Du tome'),
              ),
              TextField(
                controller: toCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Au tome'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Posséder'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final from = int.tryParse(fromCtrl.text.trim()) ?? 1;
      final to = int.tryParse(toCtrl.text.trim()) ?? from;
      await _service.markVolumesOwned(
        series: series,
        fromVolume: from,
        toVolume: to,
      );
      await _load(silent: true);
    } finally {
      fromCtrl.dispose();
      toCtrl.dispose();
    }
  }

  Future<void> _changeSubcategory() async {
    final series = _series!;
    final chosen = await showModalBottomSheet<BookSubcategory>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Catégorie de la série')),
            for (final sub in BookSubcategory.filterChips)
              ListTile(
                leading: Icon(sub.icon, color: sub.color),
                title: Text(sub.label),
                selected: series.subcategory == sub,
                onTap: () => Navigator.pop(ctx, sub),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == series.subcategory) return;
    await _service.updateSeries(series.copyWith(subcategory: chosen));
    await _load(silent: true);
  }

  Future<void> _cleanupVolumes() async {
    final series = _series!;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🧹 Réinitialiser / Nettoyer'),
        content: const Text(
          'Dédupliquer les tomes en double, ou tout remettre à « manquant » ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'dedupe'),
            child: const Text('Nettoyer doublons'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reset'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Tout décocher'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'dedupe') {
      final r = await _service.cleanupSeriesVolumes(series.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${r.removedDupes} doublon(s) retiré(s) · ${r.ownedLeft} possédé(s)',
            ),
          ),
        );
      }
    } else if (choice == 'reset') {
      final n = await _service.resetOwnedVolumes(series.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n tome(s) décoché(s)')),
        );
      }
    }
    await _load(silent: true);
  }

  Future<void> _setSeriesCoverFrom(BookVolumeSlot slot) async {
    final url = slot.volume.coverUrl ?? slot.item?.imageUrl;
    if (url == null || url.isEmpty || _series == null) return;
    final meta = Map<String, dynamic>.from(_series!.metadata);
    meta['cover_locked'] = true;
    final updated = _series!.copyWith(coverUrl: url, metadata: meta);
    setState(() => _series = updated);
    try {
      await _service.updateSeries(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _setVolumeRating(BookVolumeSlot slot, double? rating) async {
    final owned = _slotOwned(slot);
    if (rating == null) {
      _patchSlotLocal(slot, clearRating: true);
    } else {
      _patchSlotLocal(slot, rating: rating, applyRating: true, read: true);
    }
    // ignore: unawaited_futures
    () async {
      if (!owned) {
        await _service.setVolumeReadFlag(
          slot.volume.id,
          rating != null || _slotRead(slot),
        );
        await _service.patchVolumeMetadata(slot.volume.id, {
          'personal_rating': rating,
          if (rating != null) 'is_read': true,
        });
        return;
      }
      var item = slot.item;
      if (item == null || item.id.startsWith('local-')) {
        await _service.toggleVolumeOwned(
          series: _series!,
          slot: slot,
          owned: true,
        );
      }
      final items = await _service.fetchSeriesItems(_series!.id);
      final real = items.cast<CollectionItem?>().firstWhere(
            (i) => i?.volumeId == slot.volume.id && !(i?.isWishlist ?? true),
            orElse: () => null,
          );
      if (real == null) return;
      if (rating != null) await _service.setItemRead(real.id, true);
      await _service.setItemRating(real.id, rating);
    }();
  }

  void _openCover(String? url) {
    if (url == null || url.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: MediaQuery.sizeOf(ctx).width - 24,
          height: MediaQuery.sizeOf(ctx).height * 0.86,
          child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: const ColoredBox(color: Colors.black87),
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onTap: () {},
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: CollectionCoverImage(
                    url: url,
                    bookCover: true,
                    width: 420,
                    height: 640,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _series == null) {
      return Scaffold(
        appBar: AppAppBar(
          title: 'Série',
          backgroundColor: BookAccent.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final series = _series!;
    final stats = _stats!;
    final accent = BookAccent.primary;
    final physical = _physicalSlots;
    final chapters = _chapterSlots;

    return Scaffold(
      appBar: AppAppBar(
        title: series.name,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Rechercher un tome',
            icon: const Icon(Icons.search),
            onPressed: () async {
              await BookItemAddCoordinator(context).addVolumeFromCatalog(
                seriesId: series.id,
                seriesName: series.name,
                subcategory: series.subcategory,
                expectedVolumeCount: series.expectedVolumeCount,
              );
              await _load(silent: true);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'range') await _markRangeOwned();
              if (v == 'tome') {
                await showBookManualVolumeDialog(
                  context,
                  series: series,
                  service: _service,
                );
                await _load(silent: true);
              }
              if (v == 'refresh') await _refreshPublications();
              if (v == 'count') await _editExpectedCount();
              if (v == 'cleanup') await _cleanupVolumes();
              if (v == 'delete') await _confirmDelete(series);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'range',
                child: Text('⚡ Cocher une plage (X→Y)'),
              ),
              const PopupMenuItem(
                value: 'tome',
                child: Text('+ Ajouter un tome'),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Text(
                  _refreshingPubs
                      ? 'Actualisation…'
                      : '🔄 Actualiser les parutions',
                ),
              ),
              const PopupMenuItem(
                value: 'count',
                child: Text('Ajuster le nombre de tomes'),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: Text('🧹 Réinitialiser / Nettoyer les tomes'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Supprimer la série'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        color: accent,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _buildHero(series, stats, accent),
            _buildSynopsis(series),
            _buildFilterMenu(accent),
            _buildHybridFrise(physical, accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _buildCoverGrid(physical, accent),
            ),
            if (chapters.isNotEmpty) _buildChaptersSection(chapters, accent),
          ],
        ),
      ),
    );
  }

  Widget _buildChaptersSection(List<BookVolumeSlot> chapters, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.red.shade900.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () =>
                  setState(() => _chaptersExpanded = !_chaptersExpanded),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Text('🌐', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chapitres / Scans en ligne (${chapters.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      _chaptersExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.red.shade200,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_chaptersExpanded) ...[
            const SizedBox(height: 8),
            Text(
              'Ces entrées ne comptent pas dans la numérotation des tomes reliés.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            _buildCoverGrid(chapters, accent, chapterBadge: true),
          ],
        ],
      ),
    );
  }

  Widget _buildHero(BookSeries series, BookSeriesStats stats, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openCover(series.coverUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: series.coverUrl != null && series.coverUrl!.isNotEmpty
                  ? CollectionCoverImage(
                      url: series.coverUrl!,
                      width: 96,
                      height: 140,
                      bookCover: true,
                    )
                  : CoverImagePlaceholder(
                      bookCover: true,
                      width: 96,
                      height: 140,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                InkWell(
                  onTap: _changeSubcategory,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: series.subcategory.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: series.subcategory.color.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      series.subcategory.label,
                      style: TextStyle(
                        color: series.subcategory.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (stats.communityRating != null && stats.communityRating! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Text(
                      '★ ${stats.communityRating!.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (stats.displayRating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF38BDF8)),
                    ),
                    child: Text(
                      '★ ${stats.displayRating!.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  series.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _seriesStatsLine(stats),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: stats.ownedProgress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade800,
                    color: stats.isComplete
                        ? Colors.green.shade600
                        : const Color(0xFF26A69A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSynopsis(BookSeries series) {
    final text = BookVfEdition.cleanSynopsis(series.description) ?? '';
    if (text.length < 20) return const SizedBox.shrink();
    final pages = BookVfEdition.synopsisPages(text);
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = _synopsisPage.clamp(0, pages.length - 1);
    final last = page >= pages.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _synopsisVisible ? 'Masquer le synopsis' : 'Synopsis',
                onPressed: () =>
                    setState(() => _synopsisVisible = !_synopsisVisible),
                icon: const Text('💬', style: TextStyle(fontSize: 18)),
              ),
              if (!_synopsisVisible)
                Text(
                  'Synopsis',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
            ],
          ),
          if (_synopsisVisible)
            GestureDetector(
              onTap: pages.length < 2
                  ? null
                  : () => setState(() {
                        _synopsisPage = last ? 0 : page + 1;
                      }),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: BookAccent.primary.withValues(alpha: 0.85),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                pages[page],
                                key: ValueKey(page),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            if (pages.length > 1) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  last
                                      ? '↺ Début'
                                      : '▸ Suite (${page + 1}/${pages.length})',
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 0,
                    child: CustomPaint(
                      size: const Size(14, 8),
                      painter: _BubbleTailPainter(
                        fill: const Color(0xFF1E293B),
                        border: BookAccent.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<(String, String)> _languageOptions(BookSubcategory? sub) {
    return switch (sub) {
      BookSubcategory.manga => const [
          ('fr', '🇫🇷 Français (VF)'),
          ('ja', '🇯🇵 Japonais (VO)'),
          ('en', '🇬🇧 Anglais'),
        ],
      BookSubcategory.bd => const [
          ('fr', '🇫🇷 Français (Original)'),
          ('en', '🇬🇧 Anglais'),
          ('other', '🌍 Autre'),
        ],
      _ => const [
          ('fr', '🇫🇷 Français (VF)'),
          ('en', '🇬🇧 Anglais (VO)'),
          ('other', '🌍 Autre'),
        ],
    };
  }

  String _filterLabel(_VolumeFilter f) => switch (f) {
        _VolumeFilter.all => 'Tous (${_countFilter(f)})',
        _VolumeFilter.owned => 'Possédés (${_countFilter(f)})',
        _VolumeFilter.missing => 'Manquants (${_countFilter(f)})',
        _VolumeFilter.toRead => 'À lire (${_countFilter(f)})',
        _VolumeFilter.wishlist => 'Wishlist (${_countFilter(f)})',
      };

  Widget _buildFilterMenu(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<_VolumeFilter>(
          initialValue: _filter,
          onSelected: (f) => setState(() => _filter = f),
          itemBuilder: (_) => [
            for (final f in _VolumeFilter.values)
              PopupMenuItem(
                value: f,
                child: Text(_filterLabel(f)),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🌪️ ', style: TextStyle(fontSize: 13)),
                Text(
                  'Filtre : ${_filterLabel(_filter)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Frise hybride : barre statut 4px + corps note IMDb (ou gris).
  /// Au-delà de 14 tomes : aperçu 2 lignes + bouton étendre.
  Widget _buildHybridFrise(List<BookVolumeSlot> slots, Color accent) {
    if (slots.isEmpty) return const SizedBox.shrink();
    const previewLimit = 14;
    final collapsed = slots.length > previewLimit && !_friseExpanded;
    final shown = collapsed ? slots.take(previewLimit).toList() : slots;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Frise',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final slot in shown) _friseCell(slot),
            ],
          ),
          if (slots.length > previewLimit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _friseExpanded = !_friseExpanded),
                icon: Icon(
                  _friseExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                ),
                label: Text(
                  _friseExpanded
                      ? '🔼 Réduire la frise'
                      : '🔽 Voir toute la frise (${slots.length} tomes)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _friseCell(BookVolumeSlot slot) {
    final owned = _slotOwned(slot);
    final read = _slotRead(slot);
    final note = _slotRating(slot);
    final bg = owned
        ? const Color(0xFF10B981).withValues(alpha: 0.22)
        : const Color(0xFF1E293B);
    final border = owned ? const Color(0xFF10B981) : const Color(0xFF334155);
    return SizedBox(
      width: 44,
      height: note == null ? 40 : 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onFriseTap(slot),
          borderRadius: BorderRadius.circular(6),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Column(
              children: [
                if (read)
                  Container(
                    height: 3.5,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFBBF24),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: note == null
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        'T${slot.volume.displayNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      if (note != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: ratingColor(note),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            note.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
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

  ({int maxVf, int? firstUpcomingVf}) _vfExtent() {
    var maxVf = 0;
    int? firstUpcoming;
    for (final s in _slots) {
      if (s.volume.isHorsSerie || s.volume.isChapterOrScan) continue;
      final n = s.volume.volumeNumber.round();
      if (n < 1) continue;
      final md = BookSeriesService.isMangaDexCoverUrl(s.volume.coverUrl);
      if (s.volume.isUpcoming && !md) {
        if (firstUpcoming == null || n < firstUpcoming) firstUpcoming = n;
        if (n > maxVf) maxVf = n;
        continue;
      }
      if (!md && (s.volume.coverUrl != null || s.volume.publishedDate != null)) {
        if (n > maxVf) maxVf = n;
      }
    }
    return (maxVf: maxVf, firstUpcomingVf: firstUpcoming);
  }

  bool get _vfRunComplete =>
      _series?.subcategory == BookSubcategory.manga &&
      _series?.metadata['vf_complete'] == true;

  bool _slotNotYetInFrance(
    BookVolumeSlot slot, {
    required int maxVf,
    int? firstUpcomingVf,
  }) {
    if (slot.volume.isHorsSerie || slot.volume.isChapterOrScan) return false;
    final n = slot.volume.volumeNumber.round();
    if (_vfRunComplete) {
      final total = _series?.expectedVolumeCount;
      if (total == null || total < 1 || n <= total) return false;
    }
    if (firstUpcomingVf != null && n > firstUpcomingVf) return true;
    return maxVf > 0 && n > maxVf;
  }

  bool _slotShowsVoCover(
    BookVolumeSlot slot, {
    required int maxVf,
    int? firstUpcomingVf,
  }) {
    if (_slotNotYetInFrance(
      slot,
      maxVf: maxVf,
      firstUpcomingVf: firstUpcomingVf,
    )) {
      return false;
    }
    return BookSeriesService.isMangaDexCoverUrl(slot.volume.coverUrl);
  }

  Widget _buildCoverGrid(
    List<BookVolumeSlot> slots,
    Color accent, {
    bool chapterBadge = false,
  }) {
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Aucun tome pour ce filtre.',
          style: TextStyle(color: Colors.grey.shade500),
          textAlign: TextAlign.center,
        ),
      );
    }

    final vf = _vfExtent();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: slots.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.62,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (ctx, i) {
        final slot = slots[i];
        final owned = _slotOwned(slot);
        final read = _slotRead(slot);
        final rating = slot.item?.rating;
        final onFive = rating == null
            ? null
            : (rating > 5.0 ? rating / 2 : rating);
        final key = _slotKeys.putIfAbsent(slot.volume.id, GlobalKey.new);
        final coverUrl = slot.volume.coverUrl ?? slot.item?.imageUrl;
        final isChapter = chapterBadge || slot.volume.isChapterOrScan;
        final showJp = _series?.subcategory == BookSubcategory.manga;
        final japanOnly = showJp &&
            !isChapter &&
            _slotNotYetInFrance(
              slot,
              maxVf: vf.maxVf,
              firstUpcomingVf: vf.firstUpcomingVf,
            );
        final voCover = showJp &&
            !isChapter &&
            _slotShowsVoCover(
              slot,
              maxVf: vf.maxVf,
              firstUpcomingVf: vf.firstUpcomingVf,
            );
        final upcoming = !isChapter && slot.volume.isUpcoming;
        final jpBadge = upcoming
            ? (slot.volume.upcomingLabel ?? '⏳ À paraître')
            : japanOnly
                ? '🇯🇵 Paru au Japon'
                : (voCover ? '🇯🇵 Couv. VO (Japon)' : null);
        final jpIsUpcoming = upcoming;

        final editionBadge = slot.volume.editionBadge;

        return KeyedSubtree(
          key: key,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onCardTap(slot),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isChapter
                        ? Colors.red.shade400
                        : owned
                            ? const Color(0xFF26A69A)
                            : Colors.transparent,
                    width: (owned || isChapter) ? 2 : 0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: owned || read ? 1 : 0.45,
                      child: coverUrl != null && coverUrl.isNotEmpty
                          ? CollectionCoverImage(
                              url: coverUrl,
                              bookCover: true,
                              fit: BoxFit.cover,
                            )
                          : ColoredBox(
                              color: Colors.grey.shade800,
                              child: Center(
                                child: Text(
                                  isChapter
                                      ? 'Ch.${slot.volume.displayNumber}'
                                      : 'T${slot.volume.displayNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (isChapter)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SCAN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    if (jpBadge != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        right: jpIsUpcoming ? 6 : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: jpIsUpcoming
                                ? Colors.deepPurple.shade700
                                : const Color(0xFF1B2838),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(color: Colors.black45, blurRadius: 3),
                            ],
                          ),
                          child: Text(
                            jpBadge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (editionBadge != null)
                      Positioned(
                        top: jpBadge != null || slot.volume.isUpcoming ? 40 : 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC9A227),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: Text(
                            editionBadge,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Tome ${slot.volume.displayNumber}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _toggleOwned(slot),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: owned
                                            ? const Color(0xFF26A69A)
                                            : Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        owned ? '✓ Possédé' : '+ Possédé',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _toggleRead(slot),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: read
                                            ? Colors.amber.shade800
                                            : Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        read ? '👁️ Lu' : '👁️ Non lu',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (onFive != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '★ ${onFive.toStringAsFixed(1)}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF38BDF8),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheetActionButton({
    required bool active,
    required Color activeColor,
    required String activeLabel,
    required String idleLabel,
    required VoidCallback onTap,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    if (active) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: activeColor,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          shape: shape,
        ),
        child: Text(activeLabel),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        shape: shape,
      ),
      child: Text(idleLabel),
    );
  }

  Widget _buildVolumeDrawer(
    BookVolumeSlot slot,
    Color accent, {
    bool inSheet = false,
    VoidCallback? onSheetChanged,
  }) {
    final owned = _slotOwned(slot);
    final read = _slotRead(slot);
    final wish = _slotWish(slot);
    final edition = slot.volume.edition;
    final upcoming = slot.volume.upcomingLabel;
    final vf = _vfExtent();
    final showJp = _series?.subcategory == BookSubcategory.manga;
    final japanOnly = showJp &&
        _slotNotYetInFrance(
      slot,
      maxVf: vf.maxVf,
      firstUpcomingVf: vf.firstUpcomingVf,
    );
    final voCover = showJp &&
        _slotShowsVoCover(
      slot,
      maxVf: vf.maxVf,
      firstUpcomingVf: vf.firstUpcomingVf,
    );
    final lang = slot.volume.editionLanguage;
    return Card(
      margin: inSheet
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: inSheet ? 0 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openCover(slot.volume.coverUrl),
              child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 104,
                child: slot.volume.coverUrl != null
                    ? CollectionCoverImage(
                        url: slot.volume.coverUrl!,
                        bookCover: true,
                        fit: BoxFit.cover,
                      )
                    : ColoredBox(
                        color: Colors.grey.shade800,
                        child: Center(
                          child: Text(
                            'T${slot.volume.displayNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
              ),
            ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.volume.displayTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (upcoming != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      upcoming,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB39DDB),
                      ),
                    ),
                  ] else if (japanOnly) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '🇯🇵 Paru au Japon',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF90A4AE),
                      ),
                    ),
                  ] else if (voCover) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '🇯🇵 Couv. VO (Japon)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF90A4AE),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _sheetActionButton(
                        active: owned,
                        activeColor: const Color(0xFF0D9488),
                        activeLabel: '✓ Possédé',
                        idleLabel: '+ Possédé',
                        onTap: () {
                          _toggleOwned(slot);
                          onSheetChanged?.call();
                        },
                      ),
                      _sheetActionButton(
                        active: read,
                        activeColor: const Color(0xFF1565C0),
                        activeLabel: '✓ Lu',
                        idleLabel: '👁 Non lu',
                        onTap: () {
                          _toggleRead(slot);
                          onSheetChanged?.call();
                        },
                      ),
                      _sheetActionButton(
                        active: wish,
                        activeColor: const Color(0xFF6A1B9A),
                        activeLabel: '♥ Wishlist',
                        idleLabel: '♡ Wishlist',
                        onTap: () {
                          _toggleWishlist(slot);
                          onSheetChanged?.call();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Édition',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in BookVolumeEdition.values)
                        ChoiceChip(
                          label: Text(
                            e.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: edition == e
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: edition == e ? Colors.white : null,
                            ),
                          ),
                          selected: edition == e,
                          selectedColor: accent,
                          checkmarkColor: Colors.white,
                          onSelected: (_) {
                            _setEdition(slot, e);
                            onSheetChanged?.call();
                          },
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Langue de l\'exemplaire',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final opt in _languageOptions(_series?.subcategory))
                        ChoiceChip(
                          label: Text(
                            opt.$2,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  lang == opt.$1 ? FontWeight.w800 : FontWeight.w500,
                              color: lang == opt.$1 ? Colors.white : null,
                            ),
                          ),
                          selected: lang == opt.$1,
                          selectedColor: accent,
                          checkmarkColor: Colors.white,
                          onSelected: (_) {
                            _setEditionLanguage(slot, opt.$1);
                            onSheetChanged?.call();
                          },
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Note /5',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  PrecisionStarRatingBar(
                    starSize: 28,
                    rating: _slotRating(slot),
                    onChanged: (v) {
                      _setVolumeRating(slot, v);
                      onSheetChanged?.call();
                    },
                  ),
                  TextButton.icon(
                    onPressed: () => _setSeriesCoverFrom(slot),
                    icon: const Icon(Icons.image, size: 16),
                    label: const Text('Définir comme couverture de la série'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editExpectedCount() async {
    final series = _series!;
    final controller = TextEditingController(
      text: '${series.expectedVolumeCount ?? _slots.length}',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de tomes'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Total estimé'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result < 1) return;
    await _service.ensureVolumeSlots(series.id, result);
    await _service.updateSeries(
      series.copyWith(expectedVolumeCount: result),
    );
    await _load(silent: true);
  }

  Future<void> _confirmDelete(BookSeries series) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la série ?'),
        content: Text('« ${series.name} » sera retirée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.deleteSeries(series.id);
    BooksCollectionCache.instance.clear();
    if (mounted) Navigator.pop(context);
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color border;

  const _BubbleTailPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.25, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}

