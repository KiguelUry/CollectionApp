import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/storage_location.dart';

class LocationService {
  final _client = Supabase.instance.client;

  Future<List<StorageLocation>> fetchLocations({String? groupId}) async {
    final dynamic data;
    if (groupId == null) {
      data = await _client.from('locations').select().order('label');
    } else {
      data = await _client
          .from('locations')
          .select()
          .or('group_id.eq.$groupId,group_id.is.null')
          .order('label');
    }
    return (data as List)
        .map((e) => StorageLocation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<StorageLocation> createLocation({
    required String label,
    String? groupId,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('locations')
        .insert({
          'label': label.trim(),
          'created_by': userId,
          'group_id': groupId,
        })
        .select()
        .single();
    return StorageLocation.fromJson(Map<String, dynamic>.from(row));
  }
}
