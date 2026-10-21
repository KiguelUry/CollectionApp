import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/collection_category.dart';
import '../services/collection_change_history_service.dart';
import '../services/collection_refresh.dart';
import '../utils/app_page_route.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

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
          final events = snap.data ?? const [];
          if (events.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Aucune modification récente.\n'
                  'Ajouts, suppressions et changements de lieu apparaissent ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final e = events[index];
                return _TimelineTile(
                  event: e,
                  category: widget.category,
                  isFirst: index == 0,
                  isLast: index == events.length - 1,
                  onRestore: e.action == 'deleted' ? () => _restore(e) : null,
                );
              },
            ),
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

  ({IconData icon, Color color, String label}) get _badge {
    return switch (event.action) {
      'added' => (
          icon: Icons.add_rounded,
          color: Colors.green.shade700,
          label: '+ Ajout',
        ),
      'deleted' => (
          icon: Icons.delete_outline,
          color: Colors.red.shade700,
          label: 'Supprimé',
        ),
      'location' => (
          icon: Icons.place_outlined,
          color: Colors.deepOrange.shade600,
          label: 'Lieu modifié',
        ),
      'loaned' => (
          icon: Icons.handshake_outlined,
          color: Colors.blue.shade700,
          label: 'Prêté',
        ),
      'returned' => (
          icon: Icons.undo_rounded,
          color: Colors.teal.shade700,
          label: 'Rendu',
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _badge;
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
                          if (event.detail != null &&
                              event.detail!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              event.detail!,
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
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ],
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
