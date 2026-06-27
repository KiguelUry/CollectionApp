import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../services/boardgame_expansion_service.dart';
import 'boardgame_cover.dart';

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

Future<CollectionItem?> findOwnedBaseBoardgame(String baseBggId) =>
    BoardgameExpansionService().findBaseByBggId(baseBggId);

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
        'L\'ajouter aussi à ta collection et ranger cette extension dedans ?',
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

/// Ajout BGG avec règles extension (`is_expansion` + `parent_game_id`).
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
  if (isWishlist) return null;

  final link = boardgameExpansionLinkFromDetails(bggDetails);
  if (!link.isExpansion ||
      link.baseBggId == null ||
      link.baseBggId!.isEmpty) {
    return null;
  }

  final service = BoardgameExpansionService();
  final existingBase = await service.findBaseByBggId(link.baseBggId!);

  if (existingBase != null) {
    await service.linkExpansionToBase(
      base: existingBase,
      expansionBggId: bggId,
      title: title,
      bggDetails: bggDetails,
      imageUrl: imageUrl,
      minPlayers: minPlayers,
      maxPlayers: maxPlayers,
      playingTime: playingTime,
    );
    return 'Extension rangée sous « ${existingBase.title} »';
  }

  if (!context.mounted) return null;
  final addBase = await askAddBaseGameToo(
    context,
    baseTitle: link.baseTitle ?? 'le jeu de base',
  );
  if (addBase == null) return null;

  if (addBase) {
    final baseDetails = await BggService.getGameFullDetails(link.baseBggId!);
    final base = await _insertBaseGame(
      baseBggId: link.baseBggId!,
      baseTitle: link.baseTitle ?? title,
      baseDetails: baseDetails,
      locationUserId: locationUserId,
    );
    await service.linkExpansionToBase(
      base: base,
      expansionBggId: bggId,
      title: title,
      bggDetails: bggDetails,
      imageUrl: imageUrl,
      minPlayers: minPlayers,
      maxPlayers: maxPlayers,
      playingTime: playingTime,
    );
    return '« ${base.title} » ajouté avec l\'extension';
  }

  await service.insertOrphanExpansion(
    title: title,
    expansionBggId: bggId,
    baseBggId: link.baseBggId!,
    baseTitle: link.baseTitle,
    bggDetails: bggDetails,
    imageUrl: imageUrl,
    quantity: quantity,
    locationId: locationId,
    groupId: groupId,
    minPlayers: minPlayers,
    maxPlayers: maxPlayers,
    playingTime: playingTime,
  );
  return '« $title » ajouté (extension de ${link.baseTitle ?? 'jeu de base'})';
}

Future<CollectionItem> _insertBaseGame({
  required String baseBggId,
  required String baseTitle,
  Map<String, dynamic>? baseDetails,
  String? locationUserId,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser!.id;
  final meta = <String, dynamic>{'bgg_id': baseBggId};
  if (baseDetails != null) {
    for (final key in [
      'year_published',
      'min_age',
      'bgg_categories',
      'bgg_short_description',
      'bgg_avg_rating',
      'bgg_best_players',
    ]) {
      final v = baseDetails[key];
      if (v != null) meta[key] = v;
    }
  }

  final inserted = await client
      .from('collection_items')
      .insert({
        'title': baseTitle,
        'category': CollectionCategory.boardgame.dbValue,
        'metadata': meta,
        'image_url': boardgameStorageImageUrl(details: baseDetails),
        'is_wishlist': false,
        'quantity': 1,
        'added_by': userId,
        'location_user_id': locationUserId ?? userId,
        'is_expansion': false,
        'min_players': baseDetails?['min_players'],
        'max_players': baseDetails?['max_players'],
        'playing_time': baseDetails?['playing_time'],
      })
      .select()
      .single();

  return CollectionItem.fromJson(Map<String, dynamic>.from(inserted));
}

/// Rattache une extension orpheline au jeu de base (crée la base si besoin).
Future<CollectionItem?> promoteOrphanExpansionToBase({
  required CollectionItem orphanExpansion,
}) async {
  try {
    return await BoardgameExpansionService().promoteOrphanToBase(
      orphan: orphanExpansion,
    );
  } catch (_) {
    return null;
  }
}

/// Legacy : synchronise metadata ou lie une ligne extension existante.
Future<bool> attachExpansionToBaseItem({
  required CollectionItem baseItem,
  required String expansionBggId,
}) async {
  final service = BoardgameExpansionService();
  final existing = await service.findExpansionByBggId(expansionBggId);
  if (existing != null && existing.id != baseItem.id) {
    await service.linkExistingItemToBase(
      base: baseItem,
      expansion: existing,
    );
    return true;
  }
  await service.attachExpansionMetadataOnly(
    base: baseItem,
    expansionBggId: expansionBggId,
  );
  return true;
}
