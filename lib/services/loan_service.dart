import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../utils/collection_item_scope.dart';

class LoanService {
  final _client = Supabase.instance.client;

  static const _select =
      '*, locations(label), groups(name), loaned_to:profiles!loaned_to_id(username)';

  /// Objets actuellement prêtés (par toi).
  Future<List<CollectionItem>> fetchActiveLoans() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) return [];

    final rows = await CollectionItemScope.personal(
      _client
          .from('collection_items')
          .select(_select)
          .or('loaned_to_id.not.is.null,loaned_to_name.not.is.null'),
      userId: userId,
    ).order('loaned_at', ascending: false);

    return (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<CollectionItem> lendToFriend({
    required String itemId,
    required String profileId,
    required String displayName,
  }) async {
    final row = await _client
        .from('collection_items')
        .update({
          'loaned_to_id': profileId,
          'loaned_to_name': displayName.trim(),
          'loaned_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', itemId)
        .select(_select)
        .single();

    return CollectionItem.fromJson(Map<String, dynamic>.from(row));
  }

  Future<CollectionItem> lendToExternal({
    required String itemId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Indique le nom de la personne');
    }

    final row = await _client
        .from('collection_items')
        .update({
          'loaned_to_id': null,
          'loaned_to_name': trimmed,
          'loaned_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', itemId)
        .select(_select)
        .single();

    return CollectionItem.fromJson(Map<String, dynamic>.from(row));
  }

  Future<CollectionItem> returnItem(String itemId) async {
    final row = await _client
        .from('collection_items')
        .update({
          'loaned_to_id': null,
          'loaned_to_name': null,
          'loaned_at': null,
        })
        .eq('id', itemId)
        .select(_select)
        .single();

    return CollectionItem.fromJson(Map<String, dynamic>.from(row));
  }
}
