class RestaurantVisit {
  final String id;
  final String itemId;
  final String userId;
  final DateTime visitedAt;
  final int? rating;
  final String? review;
  final List<Map<String, dynamic>> dishes;
  final String? withFriendId;
  final String? withFriendName;
  final double? latitude;
  final double? longitude;

  const RestaurantVisit({
    required this.id,
    required this.itemId,
    required this.userId,
    required this.visitedAt,
    this.rating,
    this.review,
    this.dishes = const [],
    this.withFriendId,
    this.withFriendName,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;

  factory RestaurantVisit.fromJson(Map<String, dynamic> json) {
    final rawDishes = json['dishes'];
    return RestaurantVisit(
      id: json['id'] as String,
      itemId: json['item_id'] as String,
      userId: json['user_id'] as String,
      visitedAt: DateTime.parse(json['visited_at'] as String),
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      dishes: rawDishes is List
          ? rawDishes.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [],
      withFriendId: json['with_friend_id'] as String?,
      withFriendName: json['with_friend_name'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
