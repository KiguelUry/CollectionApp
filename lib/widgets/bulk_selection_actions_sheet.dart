import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../services/collection_refresh.dart';
import '../utils/wishlist_promote.dart';
import 'boardgame_tile_sheets.dart';
import 'bulk_group_assign_sheet.dart';

enum BulkSelectionAction { groups, location, wishlistToggle, delete }

/// Modale d'actions groupées pour la sélection multiple.
Future<BulkSelectionAction?> showBulkSelectionActionsSheet(
  BuildContext context, {
  required List<CollectionItem> selected,
  required List<CollectionGroup> groups,
  required Map<String, int> groupActivityCounts,
  required Future<void> Function(List<CollectionItem> items) onDelete,
}) {
  final hasGroups = groups.isNotEmpty;
  final allWishlist = selected.every((i) => i.isWishlist);
  final allOwned = selected.every((i) => !i.isWishlist);
  final wishlistLabel = allWishlist
      ? 'Déplacer vers Collection'
      : allOwned
          ? 'Déplacer vers Wishlist'
          : 'Basculer Wishlist / Collection';

  return showModalBottomSheet<BulkSelectionAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Actions groupées (${selected.length})',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (hasGroups)
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Attribuer à un groupe / foyer'),
                  onTap: () async {
                    final ok = await showBulkGroupManageSheet(
                      ctx,
                      items: selected,
                      groups: groups,
                      groupActivityCounts: groupActivityCounts,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(
                      ctx,
                      ok ? BulkSelectionAction.groups : null,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('Changer la localisation'),
                subtitle: const Text('Actuellement chez…'),
                onTap: () async {
                  await showBoardgameTileLocationSheet(
                    ctx,
                    item: selected.first,
                    groups: groups,
                  );
                  if (selected.length > 1) {
                    await _mirrorLocationToOthers(selected);
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, BulkSelectionAction.location);
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: Text(wishlistLabel),
                onTap: () async {
                  await _toggleWishlistBatch(selected);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, BulkSelectionAction.wishlistToggle);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
                title: Text(
                  'Supprimer la sélection',
                  style: TextStyle(color: Colors.red.shade700),
                ),
                onTap: () async {
                  await onDelete(selected);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, BulkSelectionAction.delete);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _mirrorLocationToOthers(List<CollectionItem> selected) async {
  if (selected.length < 2) return;
  try {
    final row = await Supabase.instance.client
        .from('collection_items')
        .select('location_user_id, metadata')
        .eq('id', selected.first.id)
        .maybeSingle();
    if (row == null) return;
    final ids = selected.skip(1).map((i) => i.id).toList();
    await Supabase.instance.client.from('collection_items').update({
      'location_user_id': row['location_user_id'],
      'metadata': row['metadata'],
    }).inFilter('id', ids);
    CollectionRefresh.instance.bump();
  } catch (_) {}
}

Future<void> _toggleWishlistBatch(List<CollectionItem> selected) async {
  final client = Supabase.instance.client;
  for (final item in selected) {
    if (item.isWishlist) {
      await promoteWishlistToCollection(item);
    } else {
      await client
          .from('collection_items')
          .update({'is_wishlist': true})
          .eq('id', item.id);
    }
  }
  CollectionRefresh.instance.bump();
}
