import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/discogs_service.dart';
import '../models/collection_category.dart';
import '../utils/active_categories.dart';
import '../utils/collection_item_scope.dart';
import '../utils/stats_dashboard.dart';

class CollectionStatsService {
  final _client = Supabase.instance.client;

  /// Vue d'ensemble filtrée sur les catégories actives du hub.
  Future<StatsDashboard> fetchDashboard() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return const StatsDashboard();

    final rows = await CollectionItemScope.ownedByUser(
      _client.from('collection_items').select(
        'id, title, category, quantity, purchase_price, image_url, metadata, '
        'is_wishlist, is_sold, is_for_sale, is_expansion, games_played, '
        'location_user_id, loaned_to_id, loaned_to_name',
      ),
      userId: userId,
    );
    final active = await ActiveCategories.load();
    return StatsDashboard.fromRows(
      [for (final r in rows as List) Map<String, dynamic>.from(r as Map)],
      active: active,
      meUserId: userId,
    );
  }

  /// Valeur marché Discogs estimée (médiane × quantité) pour la collection musicale.
  Future<double> fetchMusicMarketValueEstimate() async {
    if (!DiscogsService.isConfigured) return 0;

    final active = await ActiveCategories.load();
    if (!active.contains(CollectionCategory.media)) return 0;

    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return 0;

    final rows = await CollectionItemScope.personal(
      _client
          .from('collection_items')
          .select('title, metadata, quantity')
          .eq('category', CollectionCategory.media.dbValue)
          .eq('is_wishlist', false)
          .eq('is_sold', false)
          .eq('is_for_sale', false),
      userId: userId,
    );

    var total = 0.0;
    for (final row in rows as List) {
      final meta = row['metadata'];
      if (meta is! Map) continue;
      final releaseId = int.tryParse(
        '${meta['discogs_release_id'] ?? ''}',
      );
      final artist = meta['artist']?.toString();
      final title =
          meta['title']?.toString() ?? row['title']?.toString();

      final stats = await DiscogsService.fetchMarketStatsWithFallback(
        releaseId: releaseId,
        artist: artist,
        title: title,
      );
      final median = stats?.median ?? stats?.lowest;
      if (median == null) continue;

      final qty = (row['quantity'] as int?) ?? 1;
      total += median * qty;
    }
    return total;
  }
}
