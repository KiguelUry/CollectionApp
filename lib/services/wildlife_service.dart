import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wildlife_observation.dart';

class WildlifeService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<WildlifeObservation>> fetchForItem(String itemId) async {
    try {
      final rows = await _client
          .from('wildlife_observations')
          .select()
          .eq('item_id', itemId)
          .order('observed_at', ascending: false);
      return (rows as List)
          .map((r) => WildlifeObservation.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<WildlifeObservation>> fetchAllForMap() async {
    final id = _userId;
    if (id == null) return [];
    try {
      final rows = await _client
          .from('wildlife_observations')
          .select()
          .eq('user_id', id)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);
      return (rows as List)
          .map((r) => WildlifeObservation.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<WildlifeObservation?> addObservation({
    required String itemId,
    required DateTime observedAt,
    String? note,
    String? photoUrl,
    double? latitude,
    double? longitude,
    String? placeLabel,
  }) async {
    final id = _userId;
    if (id == null) return null;
    final row = await _client
        .from('wildlife_observations')
        .insert({
          'item_id': itemId,
          'user_id': id,
          'observed_at': observedAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if (photoUrl != null) 'photo_url': photoUrl,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (placeLabel != null) 'place_label': placeLabel,
        })
        .select()
        .single();
    return WildlifeObservation.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteObservation(String id) async {
    await _client.from('wildlife_observations').delete().eq('id', id);
  }
}
