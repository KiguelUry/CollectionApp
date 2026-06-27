import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_expansion.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../screens/group_detail_screen.dart';
import '../services/boardgame_expansion_service.dart';
import '../services/bgg_service.dart';
import '../services/collection_refresh.dart';
import '../services/item_group_service.dart';
import '../utils/boardgame_expansions.dart';
import '../utils/whereabouts_persistence.dart';
import '../utils/wishlist_collection_bridge.dart';
import '../utils/marketplace_status.dart';
import 'boardgame_expansion_detail_sheet.dart';
import 'bgg_network_image.dart';

Future<void> showBoardgameTileQuantitySheet(
  BuildContext context, {
  required CollectionItem item,
  required int ownedQuantity,
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BoardgameTileQuantitySheet(
      item: item,
      ownedQuantity: ownedQuantity,
      readOnly: readOnly,
    ),
  );
}

Future<void> showBoardgameTileGroupSheet(
  BuildContext context, {
  required CollectionItem item,
  required List<CollectionGroup> groups,
  Map<String, int> groupActivityCounts = const {},
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BoardgameTileGroupSheet(
      item: item,
      groups: groups,
      groupActivityCounts: groupActivityCounts,
      readOnly: readOnly,
    ),
  );
}

Future<void> showBoardgameTileExpansionSheet(
  BuildContext context, {
  required CollectionItem item,
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BoardgameTileExpansionSheet(
      item: item,
      readOnly: readOnly,
    ),
  );
}

Map<String, dynamic> _metadataWithGroups(
  Map<String, dynamic>? metadata,
  List<String> groupIds,
) =>
    metadataWithGroupIds(metadata, groupIds);

class _BoardgameTileQuantitySheet extends StatefulWidget {
  final CollectionItem item;
  final int ownedQuantity;
  final bool readOnly;

  const _BoardgameTileQuantitySheet({
    required this.item,
    required this.ownedQuantity,
    required this.readOnly,
  });

  @override
  State<_BoardgameTileQuantitySheet> createState() =>
      _BoardgameTileQuantitySheetState();
}

class _BoardgameTileQuantitySheetState
    extends State<_BoardgameTileQuantitySheet> {
  late int _ownedQuantity;
  late MarketplaceDisposition _disposition;
  bool _saving = false;

  bool get _canTransact => _ownedQuantity > 0;

  @override
  void initState() {
    super.initState();
    _ownedQuantity = widget.ownedQuantity.clamp(0, 9999);
    _disposition = marketplaceDisposition(widget.item);
  }

  Future<void> _promptRemoveFromWishlist() async {
    if (!widget.item.isWishlist || !mounted) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wishlist'),
        content: const Text(
          'Le jeu a été ajouté à ta collection.\n\n'
          'Enlever cet objet de la wishlist ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Garder en wishlist'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer de la wishlist'),
          ),
        ],
      ),
    );
    if (remove == true) {
      await removeWishlistRow(widget.item);
    }
  }

  Future<void> _changeOwnedQuantity(int next) async {
    if (widget.readOnly || _saving) return;
    final prev = _ownedQuantity;
    if (next == prev) return;

    setState(() {
      _ownedQuantity = next;
      _saving = true;
    });

    try {
      if (widget.item.isWishlist && prev == 0 && next == 1) {
        await addOneToCollectionFromWishlist(widget.item);
        if (mounted) await _promptRemoveFromWishlist();
      } else if (!widget.item.isWishlist) {
        await Supabase.instance.client
            .from('collection_items')
            .update({'quantity': next})
            .eq('id', widget.item.id);
      }
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        setState(() => _ownedQuantity = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistDisposition(MarketplaceDisposition next) async {
    if (widget.readOnly || _saving || !_canTransact) return;
    setState(() {
      _disposition = next;
      _saving = true;
    });
    try {
      final meta = metadataWithWantsTrade(
        widget.item.metadata,
        next == MarketplaceDisposition.wantsTrade,
      );
      await Supabase.instance.client.from('collection_items').update({
        'is_for_sale': next == MarketplaceDisposition.forSale,
        'is_sold': next == MarketplaceDisposition.sold,
        'metadata': meta,
      }).eq('id', widget.item.id);
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final loanLine =
        _canTransact && item.isOnLoan ? 'Prêté à ${item.loaneeDisplayName}' : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stock',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              widget.item.isWishlist
                  ? 'Exemplaires possédés (collection)'
                  : 'Exemplaires possédés',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _qtyButton(
                  icon: Icons.remove,
                  onPressed: widget.readOnly || _ownedQuantity <= 0
                      ? null
                      : () => _changeOwnedQuantity(_ownedQuantity - 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$_ownedQuantity',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _qtyButton(
                  icon: Icons.add,
                  onPressed: widget.readOnly
                      ? null
                      : () => _changeOwnedQuantity(_ownedQuantity + 1),
                ),
              ],
            ),
            if (widget.item.isWishlist && _ownedQuantity == 0) ...[
              const SizedBox(height: 12),
              Text(
                'Passe à 1 pour ajouter le jeu à ta collection.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (loanLine != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.handshake_outlined,
                      size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(loanLine)),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Statut marketplace',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (!_canTransact)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Indisponible tant que tu ne possèdes pas l\'objet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ...MarketplaceDisposition.values.map((d) {
              return RadioListTile<MarketplaceDisposition>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: d,
                groupValue: _disposition,
                onChanged: widget.readOnly || !_canTransact
                    ? null
                    : (v) {
                        if (v != null) _persistDisposition(v);
                      },
                title: Text(marketplaceDispositionLabel(d)),
              );
            }),
            if (_saving) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _qtyButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }
}

class _BoardgameTileGroupSheet extends StatefulWidget {
  final CollectionItem item;
  final List<CollectionGroup> groups;
  final Map<String, int> groupActivityCounts;
  final bool readOnly;

  const _BoardgameTileGroupSheet({
    required this.item,
    required this.groups,
    required this.groupActivityCounts,
    required this.readOnly,
  });

  @override
  State<_BoardgameTileGroupSheet> createState() =>
      _BoardgameTileGroupSheetState();
}

class _BoardgameTileGroupSheetState extends State<_BoardgameTileGroupSheet> {
  final _itemGroupService = ItemGroupService();
  late Set<String> _selected;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {};
    _load();
  }

  Future<void> _load() async {
    final ids = await _itemGroupService.fetchGroupIdsForItem(widget.item.id);
    if (!mounted) return;
    setState(() {
      _selected = ids.toSet();
      _loading = false;
    });
  }

  List<CollectionGroup> get _sortedGroups {
    final list = List<CollectionGroup>.from(widget.groups);
    list.sort((a, b) {
      final ca = widget.groupActivityCounts[a.id] ?? 0;
      final cb = widget.groupActivityCounts[b.id] ?? 0;
      final cmp = cb.compareTo(ca);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });
    return list;
  }

  Future<void> _toggleGroup(String groupId, bool checked) async {
    if (widget.readOnly || _saving) return;
    final previous = Set<String>.from(_selected);
    final next = Set<String>.from(_selected);
    if (checked) {
      next.add(groupId);
    } else {
      next.remove(groupId);
    }
    setState(() {
      _selected = next;
      _saving = true;
    });

    try {
      final ids = next.toList();
      await _itemGroupService.syncItemGroups(widget.item.id, ids);

      final first = ids.isEmpty ? null : ids.first;
      final whereabouts = buildWhereaboutsDbFields(
        widget.item,
        groupIds: ids,
      );

      await Supabase.instance.client.from('collection_items').update({
        'group_id': first,
        'location_user_id': whereabouts['location_user_id'],
        'metadata': whereabouts['metadata'],
      }).eq('id', widget.item.id);

      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        setState(() => _selected = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Groupes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (widget.groups.isEmpty)
              const Text(
                'Crée d\'abord un groupe dans le menu « Groupes ».',
              )
            else ...[
              if (_selected.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Ce jeu n\'est pas lié à un groupe.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _sortedGroups.map((g) {
                    final count = widget.groupActivityCounts[g.id] ?? 0;
                    final checked = _selected.contains(g.id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: checked,
                        onChanged: widget.readOnly
                            ? null
                            : (v) => _toggleGroup(g.id, v == true),
                      ),
                      title: Text(g.name),
                      subtitle: count > 0
                          ? Text('$count objet${count > 1 ? 's' : ''}')
                          : null,
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Colors.teal.shade600,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupDetailScreen(group: g),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
            if (_saving) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoardgameTileExpansionSheet extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;

  const _BoardgameTileExpansionSheet({
    required this.item,
    required this.readOnly,
  });

  @override
  State<_BoardgameTileExpansionSheet> createState() =>
      _BoardgameTileExpansionSheetState();
}

class _BoardgameTileExpansionSheetState
    extends State<_BoardgameTileExpansionSheet> {
  final _expansionService = BoardgameExpansionService();
  List<BggExpansion>? _expansions;
  late Set<String> _owned;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _owned = ownedExpansionBggIds(widget.item.metadata).toSet();
    _load();
  }

  Future<void> _load() async {
    final bggId = widget.item.metadata?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) {
      setState(() {
        _loading = false;
        _expansions = [];
      });
      return;
    }
    try {
      final list = await BggService.fetchExpansions(bggId);
      if (!mounted) return;
      setState(() {
        _expansions = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _expansions = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(BggExpansion exp, bool owned) async {
    if (widget.readOnly || _syncing) return;
    final previous = Set<String>.from(_owned);
    final next = Set<String>.from(_owned);
    if (owned) {
      next.add(exp.bggId);
    } else {
      next.remove(exp.bggId);
    }
    setState(() {
      _owned = next;
      _syncing = true;
    });
    try {
      if (owned) {
        await _expansionService.linkExpansionToBase(
          base: widget.item,
          expansionBggId: exp.bggId,
          title: exp.title,
          imageUrl: exp.imageUrl,
        );
      } else {
        await _expansionService.unlinkExpansionFromBase(
          base: widget.item,
          expansionBggId: exp.bggId,
        );
      }
      final synced =
          await _expansionService.ownedExpansionBggIdsForBase(widget.item);
      final meta = metadataWithOwnedExpansions(
        widget.item.metadata,
        synced.toList(),
      );
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': meta})
          .eq('id', widget.item.id);
      CollectionRefresh.instance.bump();
      if (mounted) setState(() => _owned = synced.toSet());
    } catch (e) {
      if (mounted) {
        setState(() => _owned = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Widget _expansionTile(BggExpansion exp, {required bool ownedSection}) {
    final owned = _owned.contains(exp.bggId);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: exp.imageUrl != null && exp.imageUrl!.isNotEmpty
              ? BggNetworkImage(
                  url: exp.imageUrl!,
                  fit: BoxFit.cover,
                  boxedCover: true,
                )
              : ColoredBox(
                  color: Colors.green.shade50,
                  child: Icon(
                    Icons.extension_outlined,
                    color: Colors.green.shade600,
                  ),
                ),
        ),
      ),
      title: Text(
        exp.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: widget.readOnly
          ? Icon(
              owned ? Icons.check_circle : Icons.circle_outlined,
              color: owned ? Colors.green.shade600 : Colors.grey,
            )
          : Checkbox(
              value: owned,
              onChanged: (v) => _toggle(exp, v == true),
            ),
      onTap: () => showBoardgameExpansionDetailSheet(
        context,
        expansion: exp,
        baseGameTitle: widget.item.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Extensions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_expansions == null || _expansions!.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text('Aucune extension listée sur BGG.'),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: Builder(
                  builder: (context) {
                    final all = _expansions!;
                    final ownedList =
                        all.where((e) => _owned.contains(e.bggId)).toList();
                    final missingList =
                        all.where((e) => !_owned.contains(e.bggId)).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Text(
                            'Possédées (${ownedList.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                        if (ownedList.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text('Aucune pour l\'instant.'),
                          )
                        else
                          ...ownedList.map(
                            (e) => _expansionTile(e, ownedSection: true),
                          ),
                        const Divider(height: 24),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                          child: Text(
                            'Non possédées (${missingList.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        if (missingList.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text('Tu as toutes les extensions BGG !'),
                          )
                        else
                          ...missingList.map(
                            (e) => _expansionTile(e, ownedSection: false),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}
