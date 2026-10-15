import '../models/collection_category.dart';
import '../models/collection_item.dart';

/// Préfixes de métadonnées personnelles à ne jamais envoyer à un ami.
const _privateMetaPrefixes = [
  'boardgame_plays',
  'games_played',
  'loan',
  'whereabouts',
  'holder',
  'location',
  'group',
  'purchase',
  'price',
  'paid',
  'personal',
  'notes',
  'review',
  'copied_from_friend',
  'recommended_by',
];

Map<String, dynamic> publicItemMetadata(Map<String, dynamic>? metadata) {
  if (metadata == null) return {};
  final out = <String, dynamic>{};
  for (final e in metadata.entries) {
    final k = e.key.toLowerCase();
    if (_privateMetaPrefixes.any(k.startsWith)) continue;
    out[e.key] = e.value;
  }
  return out;
}

Map<String, dynamic> buildRecommendationPayload(
  CollectionItem item, {
  required String senderUsername,
  String? message,
}) {
  return {
    'title': item.title.trim(),
    'category': item.category.dbValue,
    if (item.subcategory != null) 'subcategory': item.subcategory,
    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
      'image_url': item.imageUrl,
    'metadata': publicItemMetadata(item.metadata),
    if (item.minPlayers != null) 'min_players': item.minPlayers,
    if (item.maxPlayers != null) 'max_players': item.maxPlayers,
    if (item.playingTime != null) 'playing_time': item.playingTime,
    'sender_username': senderUsername,
    if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
  };
}

/// Objet wishlist prêt à insérer à partir d'une recommandation.
CollectionItem? wishlistDraftFromRecommendation(
  Map<String, dynamic> payload, {
  required String userId,
}) {
  final title = payload['title']?.toString().trim() ?? '';
  if (title.isEmpty) return null;
  final category = CollectionCategory.fromDbValue(
    payload['category']?.toString() ?? '',
  );
  final rawMeta = payload['metadata'];
  final meta = rawMeta is Map
      ? publicItemMetadata(Map<String, dynamic>.from(rawMeta))
      : <String, dynamic>{};
  final sender = payload['sender_username']?.toString().trim();
  if (sender != null && sender.isNotEmpty) meta['recommended_by'] = sender;
  int? asInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
  return CollectionItem(
    id: '',
    title: title,
    category: category,
    subcategory: payload['subcategory']?.toString(),
    metadata: meta,
    imageUrl: payload['image_url']?.toString(),
    isWishlist: true,
    quantity: 1,
    addedBy: userId,
    minPlayers: asInt(payload['min_players']),
    maxPlayers: asInt(payload['max_players']),
    playingTime: asInt(payload['playing_time']),
  );
}
