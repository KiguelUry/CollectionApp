import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/marketplace_listing.dart';
import '../utils/marketplace_status.dart';
import '../utils/supabase_embeds.dart';

/// Flux public vente / échange au sein des groupes.
class MarketplaceService {
  final _client = Supabase.instance.client;

  Future<Set<String>> _peerProfileIds() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return {};

    final memberRows = await _client
        .from('group_members')
        .select('group_id, profile_id')
        .neq('profile_id', me);

    final myGroups = await _client
        .from('group_members')
        .select('group_id')
        .eq('profile_id', me);
    final myGroupIds = (myGroups as List)
        .map((r) => r['group_id'] as String)
        .toSet();
    if (myGroupIds.isEmpty) return {};

    final peers = <String>{};
    for (final row in memberRows as List) {
      final gid = row['group_id'] as String?;
      final pid = row['profile_id'] as String?;
      if (gid == null || pid == null) continue;
      if (myGroupIds.contains(gid)) peers.add(pid);
    }
    return peers;
  }

  Future<List<MarketplaceListing>> fetchGroupListings() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];

    final peers = await _peerProfileIds();
    if (peers.isEmpty) return [];

    final rows = await _client
        .from('collection_items')
        .select(
          '${SupabaseEmbeds.collectionItemList}, '
          'owner:profiles!collection_items_added_by_fkey(username)',
        )
        .inFilter('added_by', peers.toList())
        .eq('is_sold', false)
        .eq('is_wishlist', false);

    final listings = <MarketplaceListing>[];
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final item = CollectionItem.fromJson(map);
      if (!isMarketplaceListing(item)) continue;

      final owner = map['owner'];
      final username = owner is Map
          ? owner['username'] as String? ?? 'Membre'
          : 'Membre';

      listings.add(
        MarketplaceListing(
          item: item,
          ownerId: item.addedBy ?? '',
          ownerUsername: username,
          disposition: marketplaceDisposition(item),
        ),
      );
    }

    listings.sort((a, b) => a.item.title.compareTo(b.item.title));
    return listings;
  }

  Future<void> sendInquiry({
    required MarketplaceListing listing,
    required String message,
    String? proposedItemId,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw StateError('Non connecté');

    await _client.from('marketplace_inquiries').insert({
      'listing_item_id': listing.item.id,
      'sender_id': me,
      'owner_id': listing.ownerId,
      'message': message.trim(),
      if (proposedItemId != null) 'proposed_item_id': proposedItemId,
    });
  }

  Future<List<MarketplaceInquiry>> fetchInquiriesForListing(
    String listingItemId,
  ) async {
    try {
      final rows = await _client
          .from('marketplace_inquiries')
          .select()
          .eq('listing_item_id', listingItemId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map(
            (r) => MarketplaceInquiry.fromJson(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }
}
