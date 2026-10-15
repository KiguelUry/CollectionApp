import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/player_alias_service.dart';
import '../utils/supabase_embeds.dart';
import 'global_play_history_service.dart';

/// Export JSON complet (collections, wishlists, parties, identités joueurs).
class AccountExportService {
  final _client = Supabase.instance.client;

  Future<Map<String, dynamic>> buildExportBundle() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Non connecté');

    await PlayerAliasService.instance.ensureLoaded();
    final history = GlobalPlayHistoryService();

    final itemRows = await _client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItemDetail)
        .or('added_by.eq.$uid,location_user_id.eq.$uid');
    final items = (itemRows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .map((i) => i.toExportJson())
        .toList();

    final orphans = await history.loadOrphans();
    final playsGlobal = await history.loadAllEntries();

    return {
      'export_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'user_id': uid,
      'collection_items': items,
      'orphan_boardgame_plays': orphans.map((o) => o.toJson()).toList(),
      'global_play_entries': playsGlobal
          .map(
            (e) => {
              'title': e.title,
              'item_id': e.itemId,
              'bgg_id': e.bggId,
              'is_orphan': e.isOrphan,
              'session': e.session.toJson(),
            },
          )
          .toList(),
      'player_identities': PlayerAliasService.instance.identities
          .map((g) => g.toJson())
          .toList(),
    };
  }

  Future<String> exportAsJsonString({bool pretty = true}) async {
    final bundle = await buildExportBundle();
    const encoder = JsonEncoder.withIndent('  ');
    return pretty ? encoder.convert(bundle) : jsonEncode(bundle);
  }
}

extension _CollectionItemExport on CollectionItem {
  Map<String, dynamic> toExportJson() => {
        'id': id,
        'title': title,
        'category': category.dbValue,
        'subcategory': subcategory,
        'metadata': metadata,
        'image_url': imageUrl,
        'is_wishlist': isWishlist,
        'quantity': quantity,
        'games_played': gamesPlayed,
        'rating': rating,
        'purchase_price': purchasePrice,
        'created_at': createdAt?.toIso8601String(),
      };
}
