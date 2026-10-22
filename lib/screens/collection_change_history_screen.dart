import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/collection_category.dart';
import '../services/collection_change_history_service.dart';
import '../services/collection_refresh.dart';
import '../utils/app_page_route.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

enum _ModifsFilter { all, collection, wishlist, places }

/// Timeline moderne des modifications de collection.
class CollectionChangeHistoryScreen extends StatefulWidget {
  final CollectionCategory category;

  const CollectionChangeHistoryScreen({
    super.key,
    required this.category,
  });

  @override
  State<CollectionChangeHistoryScreen> createState() =>
      _CollectionChangeHistoryScreenState();
}

class _CollectionChangeHistoryScreenState
    extends State<CollectionChangeHistoryScreen> {
  late Future<List<CollectionChangeEvent>> _future;
  _ModifsFilter _filter = _ModifsFilter.all;

  @override
  void initState() {
    super.initState();
    _future = CollectionChangeHistoryService.instance
        .load(category: widget.category);
    unawaited(
      CollectionChangeHistoryService.instance
          .markSeen(category: widget.category),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = CollectionChangeHistoryService.instance
          .load(category: widget.category);
    });
  }

  Future<void> _restore(CollectionChangeEvent event) async {
    try {
      final restored =
          await CollectionChangeHistoryService.instance.restoreDeleted(event);
      CollectionRefresh.instance.bump();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('« ${event.title} » restauré'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: restored == null
              ? null
              : SnackBarAction(
                  label: 'Ouvrir',
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    Navigator.push(
                      context,
                      appPageRoute(
                        builder: (_) => ItemDetailScreen(item: restored),
                      ),
                    );
                  },
                ),
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de restaurer : $e')),
      );
    }
  }

  List<CollectionChangeEvent> _applyFilter(List<CollectionChangeEvent> all) {
    return all.where((e) {
      final wish = e.snapshot['is_wishlist'] == true;
      return switch (_filter) {
        _ModifsFilter.all => true,
        _ModifsFilter.collection =>
          !wish &&
              (e.action == 'added' ||
                  e.action == 'deleted' ||
                  e.action == 'wishlist_to_collection'),
        _ModifsFilter.wishlist =>
          wish ||
              e.action == 'wishlist_to_collection' ||
              (e.action == 'added' && wish) ||
              (e.action == 'deleted' && wish),
        _ModifsFilter.places =>
          e.action == 'location' ||
              e.action == 'loaned' ||
              e.action == 'returned',
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Modifs — ${widget.category.label}'),
      ),
      body: FutureBuilder<List<CollectionChangeEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? const [];
          final events = _applyFilter(all);
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    for (final f in _ModifsFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          selected: _filter == f,
                          label: Text(switch (f) {
                            _ModifsFilter.all => 'Tout',
                            _ModifsFilter.collection => 'Collection',
                            _ModifsFilter.wishlist => 'Wishlist',
                            _ModifsFilter.places => 'Lieux & Prêts',
                          }),
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Aucune modification récente.\n'
                            'Ajouts, suppressions et changements de lieu apparaissent ici.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : events.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun événement pour ce filtre.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _reload,
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 780),
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    28,
                                  ),
                                  itemCount: events.length,
                                  itemBuilder: (context, index) {
                                    final e = events[index];
                                    return _TimelineTile(
                                      event: e,
                                      category: widget.category,
                                      isFirst: index == 0,
                                      isLast: index == events.length - 1,
                                      onRestore: e.action == 'deleted'
                                          ? () => _restore(e)
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final CollectionChangeEvent event;
  final CollectionCategory category;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onRestore;

  const _TimelineTile({
    required this.event,
    required this.category,
    required this.isFirst,
    required this.isLast,
    this.onRestore,
  });

  bool get _isWishlist => event.snapshot['is_wishlist'] == true;

  ({IconData icon, Color color, String label}) get _badge {
    final wish = _isWishlist;
    return switch (event.action) {
      'added' => wish
          ? (
              icon: Icons.favorite_border,
              color: Colors.purple.shade600,
              label: '💜 Wishlist · + Ajout',
            )
          : (
              icon: Icons.add_rounded,
              color: Colors.green.shade700,
              label: '📦 Collection · + Ajout',
            ),
      'deleted' => wish
          ? (
              icon: Icons.heart_broken_outlined,
              color: Colors.purple.shade700,
              label: '💜 Wishlist · Retiré',
            )
          : (
              icon: Icons.delete_outline,
              color: Colors.red.shade700,
              label: '📦 Collection · Supprimé',
            ),
      'wishlist_to_collection' => (
          icon: Icons.celebration_outlined,
          color: Colors.teal.shade700,
          label: '🎉 Wishlist → Collection',
        ),
      'location' => (
          icon: Icons.place_outlined,
          color: Colors.deepOrange.shade600,
          label: '📍 Lieu modifié',
        ),
      'loaned' => (
          icon: Icons.handshake_outlined,
          color: Colors.blue.shade700,
          label: '🤝 Prêté',
        ),
      'returned' => (
          icon: Icons.undo_rounded,
          color: Colors.teal.shade700,
          label: '↩ Rendu',
        ),
      _ => (
          icon: Icons.history,
          color: Colors.grey.shade700,
          label: event.action,
        ),
    };
  }

  String _relative(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'À l\'instant';
    if (d.inMinutes < 60) return 'Il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'Il y a ${d.inHours} h';
    if (d.inDays < 7) return 'Il y a ${d.inDays} j';
    return DateFormat('d MMM yyyy', 'fr_FR').format(at);
  }

  String? get _sideDetail {
    if (event.action == 'location') {
      final from = event.snapshot['from']?.toString();
      final to = event.snapshot['to']?.toString();
      if (from != null && to != null) return '$from → $to';
    }
    return event.detail;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _badge;
    final side = _sideDetail;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 22),
                  decoration: BoxDecoration(
                    color: badge.color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: event.imageUrl != null &&
                                event.imageUrl!.isNotEmpty
                            ? BggNetworkImage(
                                url: event.imageUrl!,
                                width: 52,
                                height: 52,
                                compact: true,
                                boxedCover:
                                    category == CollectionCategory.boardgame,
                              )
                            : ColoredBox(
                                color: scheme.surfaceContainerHigh,
                                child: Icon(badge.icon, color: badge.color),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badge.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: badge.color.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              badge.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: badge.color,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (side != null && side.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              side,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (event.actorUsername != null)
                                event.actorUsername!,
                              _relative(event.at),
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (onRestore != null) ...[
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: onRestore,
                              icon: const Icon(Icons.undo, size: 16),
                              label: const Text('Restaurer'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (side != null &&
                        side.isNotEmpty &&
                        event.action == 'location')
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.place, size: 14),
                          label: Text(
                            event.snapshot['to']?.toString() ?? side,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
