import 'package:flutter/material.dart';

import '../coordinators/book_item_add_coordinator.dart';
import '../utils/book_add_actions.dart';
import '../utils/book_volume_cover.dart';
import '../widgets/collection_cover_image.dart';
import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/book_volume.dart';
import '../services/book_series_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/create_book_series_dialog.dart';
import '../widgets/mark_volumes_owned_sheet.dart';
import 'book_series_overview_screen.dart';
import 'item_detail_screen.dart';
import 'novel_rating_matrix_screen.dart';

enum _VolumeFilter { all, owned, missing, wishlist, read }

enum _VolumeSort { numberAsc, numberDesc, ratingDesc, ratingAsc }

class BookSeriesDetailScreen extends StatefulWidget {
  final String seriesId;

  const BookSeriesDetailScreen({super.key, required this.seriesId});

  @override
  State<BookSeriesDetailScreen> createState() => _BookSeriesDetailScreenState();
}

class _BookSeriesDetailScreenState extends State<BookSeriesDetailScreen> {
  final _service = BookSeriesService();
  bool _loading = true;
  BookSeries? _series;
  BookSeriesStats? _stats;
  List<BookVolume> _volumes = [];
  List<BookVolumeSlot> _slots = [];
  List<BookSeries> _arcs = [];
  String? _activeArcId;
  _VolumeFilter _filter = _VolumeFilter.all;
  _VolumeSort _sort = _VolumeSort.numberAsc;
  String? _expandedVolumeId;
  bool _multiSelectMode = false;
  final Set<String> _selectedVolumeIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final series = await _service.fetchSeriesById(widget.seriesId);
      if (series == null) throw Exception('Série introuvable');

      final arcs = await _service.fetchSeries(
        subcategory: series.subcategory,
        parentSeriesId: series.id,
      );

      final targetId = _activeArcId ?? series.id;
      final volumes = await _service.fetchVolumes(targetId);
      final items = await _service.fetchSeriesItems(targetId);

      final stats = _service.computeStats(
        series: series,
        volumes: volumes,
        items: await _service.fetchSeriesItems(series.id),
      );
      final slots = _service.buildVolumeSlots(
        series: series,
        volumes: volumes,
        items: items,
      );

      if (mounted) {
        setState(() {
          _series = series;
          _arcs = arcs;
          _stats = stats;
          _volumes = volumes;
          _slots = slots;
          _loading = false;
        });
        _enrichVolumeCovers(series, volumes);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  List<BookVolumeSlot> get _filteredSlots {
    var list = List<BookVolumeSlot>.from(_slots);
    switch (_filter) {
      case _VolumeFilter.owned:
        list = list.where((s) => s.status == BookVolumeStatus.owned).toList();
      case _VolumeFilter.missing:
        list = list.where((s) => s.status == BookVolumeStatus.missing).toList();
      case _VolumeFilter.wishlist:
        list =
            list.where((s) => s.status == BookVolumeStatus.wishlist).toList();
      case _VolumeFilter.read:
        list = list
            .where((s) => s.item != null && s.item!.isRead)
            .toList();
      case _VolumeFilter.all:
        break;
    }
    list.sort((a, b) {
      switch (_sort) {
        case _VolumeSort.numberAsc:
          return a.volume.sortIndex.compareTo(b.volume.sortIndex);
        case _VolumeSort.numberDesc:
          return b.volume.sortIndex.compareTo(a.volume.sortIndex);
        case _VolumeSort.ratingDesc:
          final ra = a.item?.rating ?? -1;
          final rb = b.item?.rating ?? -1;
          return rb.compareTo(ra);
        case _VolumeSort.ratingAsc:
          final ra = a.item?.rating ?? 99;
          final rb = b.item?.rating ?? 99;
          return ra.compareTo(rb);
      }
    });
    return list;
  }

  Color _cellColor(BookVolumeSlot slot) {
    return switch (slot.status) {
      BookVolumeStatus.owned => Colors.green.shade600,
      BookVolumeStatus.wishlist => Colors.orange.shade600,
      BookVolumeStatus.missing => Colors.grey.shade400,
    };
  }

  Future<void> _toggleSeriesWishlist() async {
    final s = _series!;
    await _service.setSeriesWishlist(s.id, !s.wishlistEntireSeries);
    await _load();
  }

  bool _canBulkSelect(BookVolumeSlot slot) =>
      slot.status == BookVolumeStatus.missing;

  void _toggleMultiSelectMode() {
    setState(() {
      _multiSelectMode = !_multiSelectMode;
      if (!_multiSelectMode) {
        _selectedVolumeIds.clear();
        _expandedVolumeId = null;
      }
    });
  }

  void _toggleVolumeSelection(String volumeId, {bool? value}) {
    setState(() {
      if (value == false || _selectedVolumeIds.contains(volumeId)) {
        _selectedVolumeIds.remove(volumeId);
      } else {
        _selectedVolumeIds.add(volumeId);
      }
    });
  }

  void _selectAllMissingVisible() {
    setState(() {
      for (final slot in _filteredSlots) {
        if (_canBulkSelect(slot)) {
          _selectedVolumeIds.add(slot.volume.id);
        }
      }
    });
  }

  Future<void> _addSelectedVolumes({bool markAsRead = false}) async {
    final s = _series!;
    final numbers = <int>[];
    for (final slot in _slots) {
      if (!_selectedVolumeIds.contains(slot.volume.id)) continue;
      if (!_canBulkSelect(slot)) continue;
      numbers.add(slot.volume.volumeNumber.ceil());
    }
    if (numbers.isEmpty) return;

    final n = await _service.markVolumesOwnedNumbers(
      series: s,
      volumeNumbers: numbers,
      markAsRead: markAsRead,
    );
    if (!mounted) return;
    setState(() {
      _selectedVolumeIds.clear();
      _multiSelectMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$n tome(s) ajouté(s) à la collection')),
    );
    await _load();
  }

  Future<void> _enrichVolumeCovers(
    BookSeries series,
    List<BookVolume> volumes,
  ) async {
    final updated = await _service.enrichMissingVolumeCovers(
      series: series,
      volumes: volumes,
    );
    if (updated > 0 && mounted) await _load();
  }

  Future<void> _markVolumesOwned() async {
    final s = _series!;
    final result = await showMarkVolumesOwnedSheet(
      context,
      seriesName: s.name,
      maxVolume: s.expectedVolumeCount,
    );
    if (result == null) return;
    final n = await _service.markVolumesOwned(
      series: s,
      fromVolume: result.from,
      toVolume: result.to,
      markAsRead: result.markAsRead,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n tome(s) marqué(s) comme possédés')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    if (_loading || series == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final stats = _stats ?? const BookSeriesStats();
    return Scaffold(
      appBar: AppAppBar(
        title: series.name,
        actions: [
          if (_multiSelectMode)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Quitter la sélection',
              onPressed: _toggleMultiSelectMode,
            ),
          PopupMenuButton<String>(
            icon: Icon(
              series.wishlistEntireSeries
                  ? Icons.favorite
                  : Icons.more_vert,
              color: series.wishlistEntireSeries ? Colors.red : null,
            ),
            tooltip: 'Actions série',
            onSelected: (value) async {
              switch (value) {
                case 'add':
                  await BookItemAddCoordinator(context).addVolumeFromCatalog(
                    seriesId: series.id,
                    seriesName: series.name,
                    subcategory: series.subcategory,
                    expectedVolumeCount: series.expectedVolumeCount,
                  );
                  await _load();
                case 'select':
                  _toggleMultiSelectMode();
                case 'range':
                  await _markVolumesOwned();
                case 'wishlist':
                  await _toggleSeriesWishlist();
                case 'info':
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) =>
                          BookSeriesOverviewScreen(seriesId: series.id),
                    ),
                  );
                  await _load();
                case 'matrix':
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) =>
                          NovelRatingMatrixScreen(seriesId: series.id),
                    ),
                  );
                  await _load();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.library_add_outlined),
                    SizedBox(width: 12),
                    Text('Ajouter un tome (recherche)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'select',
                child: Row(
                  children: [
                    Icon(
                      _multiSelectMode
                          ? Icons.checklist_rtl
                          : Icons.checklist_outlined,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _multiSelectMode
                          ? 'Quitter sélection multiple'
                          : 'Sélection multiple',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'range',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add_check),
                    SizedBox(width: 12),
                    Text('Marquer une plage de tomes'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'wishlist',
                child: Row(
                  children: [
                    Icon(
                      series.wishlistEntireSeries
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: series.wishlistEntireSeries ? Colors.red : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      series.wishlistEntireSeries
                          ? 'Retirer de la wishlist'
                          : 'Wishlist série entière',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Text('Fiche série'),
                  ],
                ),
              ),
              if (series.subcategory == BookSubcategory.novel)
                const PopupMenuItem(
                  value: 'matrix',
                  child: Row(
                    children: [
                      Icon(Icons.grid_on_outlined),
                      SizedBox(width: 12),
                      Text('Matrice de notes'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (series.coverUrl != null && series.coverUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: CollectionCoverImage(
                    url: series.coverUrl!,
                    height: 120,
                    bookCover: true,
                    largeSource: true,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('Possédé ${stats.ownedLabel}')),
                Chip(label: Text('Lu ${stats.readLabel}')),
                if (stats.ratingLabel != null)
                  Chip(
                    avatar: const Icon(Icons.star, size: 16),
                    label: Text('★ ${stats.ratingLabel}'),
                  ),
              ],
            ),
          ),
          if (_arcs.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  ChoiceChip(
                    label: const Text('Principal'),
                    selected: _activeArcId == null,
                    onSelected: (_) {
                      setState(() => _activeArcId = null);
                      _load();
                    },
                  ),
                  for (final arc in _arcs)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(arc.name),
                        selected: _activeArcId == arc.id,
                        onSelected: (_) {
                          setState(() => _activeArcId = arc.id);
                          _load();
                        },
                      ),
                    ),
                  ActionChip(
                    label: const Text('+ Arc'),
                    onPressed: () async {
                      final r = await showCreateBookSeriesDialog(
                        context,
                        subcategory: series.subcategory,
                        parentName: series.name,
                      );
                      if (r == null) return;
                      await _service.createSeries(
                        name: r.name,
                        subcategory: series.subcategory,
                        parentSeriesId: series.id,
                        expectedVolumeCount: r.expectedVolumes,
                      );
                      await _load();
                    },
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _filterChip('Tous', _VolumeFilter.all),
                _filterChip('Possédés', _VolumeFilter.owned),
                _filterChip('Manquants', _VolumeFilter.missing),
                _filterChip('Wishlist', _VolumeFilter.wishlist),
                _filterChip('Lus', _VolumeFilter.read),
                const SizedBox(width: 16),
                PopupMenuButton<_VolumeSort>(
                  initialValue: _sort,
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: _VolumeSort.numberAsc,
                      child: Text('N° croissant'),
                    ),
                    PopupMenuItem(
                      value: _VolumeSort.numberDesc,
                      child: Text('N° décroissant'),
                    ),
                    PopupMenuItem(
                      value: _VolumeSort.ratingDesc,
                      child: Text('Note ↓'),
                    ),
                    PopupMenuItem(
                      value: _VolumeSort.ratingAsc,
                      child: Text('Note ↑'),
                    ),
                  ],
                  child: const Chip(
                    avatar: Icon(Icons.sort, size: 18),
                    label: Text('Tri'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _volumes.isEmpty
                ? Center(
                    child: Text(
                      'Aucun tome défini.\nDéfinis le nombre de tomes dans la fiche série.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      _multiSelectMode ? 120 : 88,
                    ),
                    itemCount: _filteredSlots.length,
                    itemBuilder: (context, i) =>
                        _buildVolumeTile(slot: _filteredSlots[i], series: series),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _multiSelectMode
          ? _buildMultiSelectBar(series)
          : null,
      floatingActionButton: _multiSelectMode
          ? null
          : FloatingActionButton(
              onPressed: () => openBookAddFlow(
                context,
                subcategory: series.subcategory,
              ).then((_) => _load()),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildVolumeTile({
    required BookVolumeSlot slot,
    required BookSeries series,
  }) {
    final expanded = !_multiSelectMode && _expandedVolumeId == slot.volume.id;
    final selected = _selectedVolumeIds.contains(slot.volume.id);
    final canSelect = _canBulkSelect(slot);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _multiSelectMode && selected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: Column(
        children: [
          ListTile(
            leading: VolumeLeading(
              slot: slot,
              fallbackColor: _cellColor(slot),
            ),
            title: Text(
              slot.volume.label ?? 'Tome ${slot.volume.displayNumber}',
            ),
            subtitle: Text(_slotSubtitle(slot)),
            trailing: _multiSelectMode
                ? Checkbox(
                    value: selected,
                    onChanged: canSelect
                        ? (v) => _toggleVolumeSelection(
                              slot.volume.id,
                              value: v == true,
                            )
                        : null,
                  )
                : Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                  ),
            onTap: () {
              if (_multiSelectMode) {
                if (canSelect) {
                  _toggleVolumeSelection(slot.volume.id);
                }
                return;
              }
              setState(() {
                _expandedVolumeId = expanded ? null : slot.volume.id;
              });
            },
            onLongPress: _multiSelectMode || !canSelect
                ? null
                : () {
                    setState(() {
                      _multiSelectMode = true;
                      _selectedVolumeIds.add(slot.volume.id);
                    });
                  },
          ),
          if (expanded) _buildExpanded(slot, series),
        ],
      ),
    );
  }

  Widget _buildMultiSelectBar(BookSeries series) {
    final count = _selectedVolumeIds.length;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Coche les tomes à ajouter, puis valide',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _selectAllMissingVisible,
                    child: const Text('Tous manquants'),
                  ),
                  TextButton(
                    onPressed: count == 0
                        ? null
                        : () => setState(() => _selectedVolumeIds.clear()),
                    child: const Text('Aucun'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed:
                        count == 0 ? null : () => _addSelectedVolumes(),
                    icon: const Icon(Icons.add),
                    label: Text('Ajouter ($count)'),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: count == 0
                    ? null
                    : () => _addSelectedVolumes(markAsRead: true),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Ajouter et marquer lus'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, _VolumeFilter f) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: _filter == f,
        onSelected: (_) => setState(() => _filter = f),
      ),
    );
  }

  String _slotSubtitle(BookVolumeSlot slot) {
    return switch (slot.status) {
      BookVolumeStatus.owned => slot.item?.isRead == true
          ? 'Possédé · Lu'
          : 'Possédé',
      BookVolumeStatus.wishlist => 'Wishlist',
      BookVolumeStatus.missing => 'Non possédé',
    };
  }

  Widget _buildExpanded(
    BookVolumeSlot slot,
    BookSeries series,
  ) {
    final item = slot.item;
    final cover = volumeCoverUrl(slot);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cover != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CollectionCoverImage(
                url: cover,
                height: 200,
                bookCover: true,
                largeSource: true,
              ),
            ),
          if (item != null) ...[
            const SizedBox(height: 8),
            if (item.rating != null)
              Text('Ma note : ${item.rating!.toStringAsFixed(1)} / 5'),
            if (item.review != null && item.review!.isNotEmpty)
              Text(item.review!, maxLines: 3, overflow: TextOverflow.ellipsis),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lu'),
              value: item.isRead,
              onChanged: (v) async {
                await _service.setItemRead(item.id, v);
                await _load();
              },
            ),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ItemDetailScreen(item: item),
                ),
              ).then((_) => _load()),
              child: const Text('Ouvrir la fiche'),
            ),
          ]           else
            FilledButton.icon(
              onPressed: () => BookItemAddCoordinator(context)
                  .addToVolume(
                    seriesId: _activeArcId ?? series.id,
                    volumeId: slot.volume.id,
                    seriesName: series.name,
                    subcategory: series.subcategory,
                    volumeNumber: slot.volume.volumeNumber,
                    expectedVolumeCount: series.expectedVolumeCount,
                  )
                  .then((_) => _load()),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter ce tome'),
            ),
        ],
      ),
    );
  }
}
