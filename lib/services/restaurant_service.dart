import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant_visit.dart';

class RestaurantService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<RestaurantVisit>> fetchForItem(String itemId) async {
    try {
      final rows = await _client
          .from('restaurant_visits')
          .select()
          .eq('item_id', itemId)
          .order('visited_at', ascending: false);
      return (rows as List)
          .map((r) => RestaurantVisit.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<RestaurantVisit>> fetchMyMapVisits() async {
    final id = _userId;
    if (id == null) return [];
    try {
      final rows = await _client
          .from('restaurant_visits')
          .select()
          .eq('user_id', id)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);
      return (rows as List)
          .map((r) => RestaurantVisit.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<RestaurantVisit>> fetchGroupMapVisits(String groupId) async {
    try {
      final itemRows = await _client
          .from('collection_items')
          .select('id')
          .eq('group_id', groupId);
      final junction = await _client
          .from('collection_item_groups')
          .select('item_id')
          .eq('group_id', groupId);
      final ids = <String>{
        for (final r in itemRows as List) r['id'] as String,
        for (final r in junction as List) r['item_id'] as String,
      };
      if (ids.isEmpty) return [];

      final rows = await _client
          .from('restaurant_visits')
          .select()
          .inFilter('item_id', ids.toList())
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);
      return (rows as List)
          .map((r) => RestaurantVisit.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<RestaurantVisit?> addVisit({
    required String itemId,
    required DateTime visitedAt,
    int? rating,
    String? review,
    List<Map<String, dynamic>> dishes = const [],
    String? withFriendId,
    String? withFriendName,
    double? latitude,
    double? longitude,
  }) async {
    final id = _userId;
    if (id == null) return null;
    final row = await _client
        .from('restaurant_visits')
        .insert({
          'item_id': itemId,
          'user_id': id,
          'visited_at': visitedAt.toIso8601String(),
          if (rating != null) 'rating': rating,
          if (review != null && review.trim().isNotEmpty) 'review': review.trim(),
          'dishes': dishes,
          if (withFriendId != null) 'with_friend_id': withFriendId,
          if (withFriendName != null) 'with_friend_name': withFriendName,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        })
        .select()
        .single();
    return RestaurantVisit.fromJson(Map<String, dynamic>.from(row));
  }
}
