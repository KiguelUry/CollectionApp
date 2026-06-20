import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/collection_refresh.dart';
import 'boardgame_cover.dart';
import 'boardgame_expansions.dart';

/// Infos extension ↔ jeu de base (metadata BGG).
class BoardgameExpansionLink {
  final bool isExpansion;
  final String? baseBggId;
  final String? baseTitle;

  const BoardgameExpansionLink({
    this.isExpansion = false,
    this.baseBggId,
    this.baseTitle,
  });
}

BoardgameExpansionLink boardgameExpansionLinkFromDetails(
  Map<String, dynamic>? details,
) {
  if (details == null) return const BoardgameExpansionLink();
  final isExp = details['bgg_is_expansion'] == true;
  final baseId = details['base_game_bgg_id']?.toString();
  final baseTitle = details['base_game_title']?.toString();
  return BoardgameExpansionLink(
    isExpansion: isExp,
    baseBggId: baseId != null && baseId.isNotEmpty ? baseId : null,
    baseTitle: baseTitle != null && baseTitle.isNotEmpty ? baseTitle : null,
  );
}

Future<CollectionItem?> findOwnedBaseBoardgame(String baseBggId) async {
  if (baseBggId.isEmpty) return null;
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return null;

  final rows = await Supabase.instance.client
      .from('collection_items')
      .select()
      .eq('category', CollectionCategory.boardgame.dbValue)
      .eq('is_wishlist', false)
      .or('added_by.eq.$userId,location_user_id.eq.$userId');

  for (final row in rows as List) {
    final meta = row['metadata'] as Map<String, dynamic>?;
    if (meta?['bgg_id']?.toString() == baseBggId) {
      return CollectionItem.fromJson(row as Map<String, dynamic>);
    }
  }
  return null;
}

Future<bool> attachExpansionToBaseItem({
  required CollectionItem baseItem,
  required String expansionBggId,
}) async {
  final owned = ownedExpansionBggIds(baseItem.metadata).toSet();
  if (owned.contains(expansionBggId)) return true;
  owned.add(expansionBggId);
  final meta = metadataWithOwnedExpansions(baseItem.metadata, owned.toList());
  await Supabase.instance.client
      .from('collection_items')
      .update({'metadata': meta})
      .eq('id', baseItem.id);
  CollectionRefresh.instance.bump();
  return true;
}

Future<bool?> askAddBaseGameToo(
  BuildContext context, {
  required String baseTitle,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Extension détectée'),
      content: Text(
        '« $baseTitle » est le jeu de base.\n\n'
        'L\'ajouter aussi à ta collection et cocher cette extension dedans ?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Non, extension seule'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Oui, ajouter la base'),
        ),
      ],
    ),
  );
}

/// Ajout BGG avec règles extension (base déjà possédée → metadata seulement).
Future<String?> insertBoardgameWithExpansionRules({
  required BuildContext context,
  required String title,
  required String bggId,
  required Map<String, dynamic>? bggDetails,
  required String? imageUrl,
  required bool isWishlist,
  required int quantity,
  String? locationId,
  String? groupId,
  String? locationUserId,
  int? minPlayers,
  int? maxPlayers,
  int? playingTime,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser!.id;
  final link = boardgameExpansionLinkFromDetails(bggDetails);

  if (!isWishlist &&
      link.isExpansion &&
      link.baseBggId != null &&
      link.baseBggId!.isNotEmpty) {
    final base = await findOwnedBaseBoardgame(link.baseBggId!);
    if (base != null) {
      await attachExpansionToBaseItem(
        baseItem: base,
        expansionBggId: bggId,
      );
      return 'Extension cochée sur « ${base.title} »';
    }

    if (!context.mounted) return null;
    final addBase = await askAddBaseGameToo(
      context,
      baseTitle: link.baseTitle ?? 'le jeu de base',
    );
    if (addBase == null) return null;

    if (addBase) {
      final baseDetails = await BggService.getGameFullDetails(link.baseBggId!);
      final baseMeta = <String, dynamic>{
        'bgg_id': link.baseBggId!,
        if (link.baseTitle != null) 'base_game_title': link.baseTitle!,
      };
      if (baseDetails != null) {
        for (final key in ['year_published', 'min_age', 'bgg_categories']) {
          final v = baseDetails[key];
          if (v != null) baseMeta[key] = v;
        }
      }
      final baseCover = boardgameStorageImageUrl(details: baseDetails);
      final baseOwned = metadataWithOwnedExpansions(baseMeta, [bggId]);
      final baseItem = CollectionItem(
        id: '',
        title: link.baseTitle ?? title,
        category: CollectionCategory.boardgame,
        metadata: baseOwned,
        imageUrl: baseCover,
        isWishlist: false,
        quantity: 1,
        minPlayers: baseDetails?['min_players'] as int?,
        maxPlayers: baseDetails?['max_players'] as int?,
        playingTime: baseDetails?['playing_time'] as int?,
      );
      await client.from('collection_items').insert(
            baseItem.toInsertJson(
              isWishlist: false,
              locationUserId: locationUserId ?? userId,
              addedBy: userId,
            ),
          );
      CollectionRefresh.instance.bump();
      return '« ${link.baseTitle ?? title} » ajouté avec l\'extension';
    }

    final orphanMeta = <String, dynamic>{
      'bgg_id': bggId,
      'expansion_of_bgg_id': link.baseBggId!,
      if (link.baseTitle != null) 'expansion_of_title': link.baseTitle!,
    };
    if (bggDetails != null) {
      for (final key in ['year_published', 'min_age', 'bgg_categories']) {
        final v = bggDetails[key];
        if (v != null) orphanMeta[key] = v;
      }
    }
    final orphan = CollectionItem(
      id: '',
      title: title.trim(),
      category: CollectionCategory.boardgame,
      metadata: orphanMeta,
      imageUrl: boardgameStorageImageUrl(details: bggDetails, catalogUrl: imageUrl),
      isWishlist: false,
      quantity: quantity,
      locationId: locationId,
      groupId: groupId,
      minPlayers: minPlayers,
      maxPlayers: maxPlayers,
      playingTime: playingTime,
    );
    await client.from('collection_items').insert(
          orphan.toInsertJson(
            isWishlist: false,
            locationUserId: locationUserId ?? userId,
            addedBy: userId,
          ),
        );
    CollectionRefresh.instance.bump();
    return '« $title » ajouté (extension de ${link.baseTitle ?? 'jeu de base'})';
  }

  return null;
}

/// Fusionne une extension orpheline dans le jeu de base (nouveau item base).
Future<CollectionItem?> promoteOrphanExpansionToBase({
  required CollectionItem orphanExpansion,
}) async {
  final baseId = orphanExpansion.metadata?['expansion_of_bgg_id']?.toString();
  if (baseId == null || baseId.isEmpty) return null;

  final client = Supabase.instance.client;
  final userId = client.auth.currentUser!.id;
  final expId = orphanExpansion.metadata?['bgg_id']?.toString();
  if (expId == null || expId.isEmpty) return null;

  final baseTitle =
      orphanExpansion.metadata?['expansion_of_title']?.toString() ??
          'Jeu de base';

  final existingBase = await findOwnedBaseBoardgame(baseId);
  if (existingBase != null) {
    await attachExpansionToBaseItem(
      baseItem: existingBase,
      expansionBggId: expId,
    );
    await client.from('collection_items').delete().eq('id', orphanExpansion.id);
    CollectionRefresh.instance.bump();
    final updatedMeta = metadataWithOwnedExpansions(
      existingBase.metadata,
      {...ownedExpansionBggIds(existingBase.metadata), expId}.toList(),
    );
    return existingBase.copyWith(metadata: updatedMeta);
  }

  final details = await _fetchBaseDetails(baseId);
  final meta = metadataWithOwnedExpansions(
    {
      'bgg_id': baseId,
      if (details?['bgg_categories'] != null)
        'bgg_categories': details!['bgg_categories'],
      if (details?['year_published'] != null)
        'year_published': details!['year_published'],
      if (details?['min_age'] != null) 'min_age': details!['min_age'],
    },
    [expId],
  );

  final inserted = await client
      .from('collection_items')
      .insert({
        'title': baseTitle,
        'category': CollectionCategory.boardgame.dbValue,
        'metadata': meta,
        'image_url': boardgameStorageImageUrl(details: details),
        'is_wishlist': false,
        'quantity': 1,
        'added_by': userId,
        'location_user_id': userId,
        'min_players': details?['min_players'],
        'max_players': details?['max_players'],
        'playing_time': details?['playing_time'],
      })
      .select()
      .single();

  await client.from('collection_items').delete().eq('id', orphanExpansion.id);
  CollectionRefresh.instance.bump();
  return CollectionItem.fromJson(Map<String, dynamic>.from(inserted));
}

Future<Map<String, dynamic>?> _fetchBaseDetails(String bggId) async {
  try {
    return BggService.getGameFullDetails(bggId);
  } catch (_) {
    return null;
  }
}
