class ActivityEvent {
  final String id;
  final String actorId;
  final String actorUsername;
  final String? actorAvatarUrl;
  final String? actorAccentColor;
  final String eventType;
  final String? itemId;
  final String? itemTitle;
  final String? itemImageUrl;
  final String? itemCategory;
  final double? rating;
  final DateTime createdAt;

  const ActivityEvent({
    required this.id,
    required this.actorId,
    required this.actorUsername,
    this.actorAvatarUrl,
    this.actorAccentColor,
    required this.eventType,
    this.itemId,
    this.itemTitle,
    this.itemImageUrl,
    this.itemCategory,
    this.rating,
    required this.createdAt,
  });

  String get description {
    final name = actorUsername;
    final item = itemTitle ?? 'un objet';
    return switch (eventType) {
      'item_added' => '$name a ajouté $item',
      'wishlist_added' => '$name a mis $item en wishlist',
      'item_rated' => '$name a noté $item${rating != null ? ' ($rating★)' : ''}',
      'trophies_updated' => '$name a mis à jour ses trophées',
      _ => '$name a une activité',
    };
  }
}
