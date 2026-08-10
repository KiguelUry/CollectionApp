import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../services/collection_change_history_service.dart';
import '../services/collection_refresh.dart';
import '../utils/app_page_route.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

/// Historique local court des ajouts / suppressions (restauration possible).
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('« ${event.title} » restauré'),
          action: restored == null
              ? null
              : SnackBarAction(
                  label: 'Ouvrir',
                  onPressed: () {
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
        title: Text('Historique — ${widget.category.label}'),
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
                  'Aucun ajout ou suppression récente.\n'
                  'Les suppressions restent restaurables ~14 jours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final e = events[index];
                final isDelete = e.action == 'deleted';
                return ListTile(
                  tileColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: e.imageUrl != null && e.imageUrl!.isNotEmpty
                          ? BggNetworkImage(
                              url: e.imageUrl!,
                              width: 48,
                              height: 48,
                              compact: true,
                              boxedCover:
                                  widget.category == CollectionCategory.boardgame,
                            )
                          : ColoredBox(
                              color: scheme.surfaceContainerHigh,
                              child: Icon(
                                isDelete
                                    ? Icons.delete_outline
                                    : Icons.add_circle_outline,
                              ),
                            ),
                    ),
                  ),
                  title: Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${isDelete ? 'Supprimé' : 'Ajouté'} · ${_fmt(e.at)}',
                  ),
                  trailing: isDelete
                      ? FilledButton.tonal(
                          onPressed: () => _restore(e),
                          child: const Text('Restaurer'),
                        )
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _fmt(DateTime at) {
    final local = at.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${hh}h$min';
  }
}
