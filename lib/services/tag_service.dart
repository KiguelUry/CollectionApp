import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/item_tag.dart';

class TagService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<ItemTag>> fetchMyTags() async {
    final id = _userId;
    if (id == null) return [];

    final rows = await _client
        .from('item_tags')
        .select()
        .eq('profile_id', id)
        .order('label');

    return (rows as List)
        .map((r) => ItemTag.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<ItemTag> createTag(String label, {String? colorHex}) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final trimmed = label.trim();
    if (trimmed.isEmpty) throw Exception('Libellé vide');

    final row = await _client
        .from('item_tags')
        .insert({
          'profile_id': id,
          'label': trimmed,
          'color': colorHex ?? tagColorPresets.first,
        })
        .select()
        .single();

    return ItemTag.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<ItemTag>> fetchTagsForItem(String itemId) async {
    final rows = await _client
        .from('collection_item_tags')
        .select('item_tags(id, label, color)')
        .eq('item_id', itemId);

    return _parseTagRows(rows as List);
  }

  Future<void> setItemTags(String itemId, List<String> tagIds) async {
    await _client
        .from('collection_item_tags')
        .delete()
        .eq('item_id', itemId);

    if (tagIds.isEmpty) return;

    await _client.from('collection_item_tags').insert(
          tagIds
              .map((tagId) => {'item_id': itemId, 'tag_id': tagId})
              .toList(),
        );
  }

  /// Attache les tags aux objets (pour filtres / liste).
  Future<List<CollectionItem>> enrichItems(List<CollectionItem> items) async {
    if (items.isEmpty) return items;

    final ids = items.map((i) => i.id).toList();
    final rows = await _client
        .from('collection_item_tags')
        .select('item_id, item_tags(id, label, color)')
        .inFilter('item_id', ids);

    final byItem = <String, List<ItemTag>>{};
    for (final row in rows as List) {
      final itemId = row['item_id'] as String;
      final tagJson = row['item_tags'];
      if (tagJson is! Map) continue;
      byItem.putIfAbsent(itemId, () => []);
      byItem[itemId]!.add(ItemTag.fromJson(Map<String, dynamic>.from(tagJson)));
    }

    return items
        .map((i) => i.copyWith(tags: byItem[i.id] ?? const []))
        .toList();
  }

  List<ItemTag> _parseTagRows(List rows) {
    final tags = <ItemTag>[];
    for (final row in rows) {
      final tagJson = row['item_tags'];
      if (tagJson is Map) {
        tags.add(ItemTag.fromJson(Map<String, dynamic>.from(tagJson)));
      }
    }
    tags.sort((a, b) => a.label.compareTo(b.label));
    return tags;
  }

}
