import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/whereabouts_persistence.dart';

/// Entrée d'historique local (ajouts / suppressions) pour restauration rapide.
class CollectionChangeEvent {
  final String id;
  final String action; // added | deleted
  final DateTime at;
  final CollectionCategory category;
  final String title;
  final String? imageUrl;
  final Map<String, dynamic> snapshot;

  const CollectionChangeEvent({
    required this.id,
    required this.action,
    required this.at,
    required this.category,
    required this.title,
    required this.imageUrl,
    required this.snapshot,
  });

  factory CollectionChangeEvent.fromJson(Map<String, dynamic> json) {
    return CollectionChangeEvent(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'deleted',
      at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
      category: CollectionCategory.fromDbValue(
        json['category']?.toString() ?? 'boardgame',
      ),
      title: json['title']?.toString() ?? 'Sans titre',
      imageUrl: json['image_url']?.toString(),
      snapshot: Map<String, dynamic>.from(json['snapshot'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'at': at.toIso8601String(),
        'category': category.dbValue,
        'title': title,
        'image_url': imageUrl,
        'snapshot': snapshot,
      };
}

/// Historique local court (SharedPreferences) — TTL 14 jours, max 80 entrées.
class CollectionChangeHistoryService {
  CollectionChangeHistoryService._();
  static final instance = CollectionChangeHistoryService._();

  static const _keyPrefix = 'collection_change_history_v1_';
  static const _ttl = Duration(days: 14);
  static const _maxEntries = 80;

  String _storageKey(String userId, CollectionCategory category) =>
      '$_keyPrefix${userId}_${category.dbValue}';

  Future<List<CollectionChangeEvent>> load({
    required CollectionCategory category,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(userId, category));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => CollectionChangeEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final cutoff = DateTime.now().subtract(_ttl);
      final kept = list.where((e) => e.at.isAfter(cutoff)).toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      if (kept.length != list.length) {
        await _save(userId, category, kept);
      }
      return kept;
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordDeleted(CollectionItem item) async {
    await _record(
      action: 'deleted',
      item: item,
      snapshot: _snapshotFromItem(item),
    );
  }

  Future<void> recordAdded(CollectionItem item) async {
    await _record(
      action: 'added',
      item: item,
      snapshot: {
        'id': item.id,
        'title': item.title,
        'category': item.category.dbValue,
        'image_url': item.imageUrl,
        'is_wishlist': item.isWishlist,
      },
    );
  }

  Future<void> _record({
    required String action,
    required CollectionItem item,
    required Map<String, dynamic> snapshot,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final events = await load(category: item.category);
    final entry = CollectionChangeEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}_${item.id}',
      action: action,
      at: DateTime.now(),
      category: item.category,
      title: item.title,
      imageUrl: item.imageUrl,
      snapshot: snapshot,
    );
    final next = [entry, ...events].take(_maxEntries).toList();
    await _save(userId, item.category, next);
  }

  Future<void> _save(
    String userId,
    CollectionCategory category,
    List<CollectionChangeEvent> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(userId, category),
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  Map<String, dynamic> _snapshotFromItem(CollectionItem item) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final payload = buildCollectionItemInsertPayload(
      item: item,
      addedBy: userId ?? item.addedBy ?? '',
      isWishlist: item.isWishlist,
      defaultUserId: userId ?? '',
    );
    // Conserver aussi l'ancien id pour affichage / debug.
    payload['_previous_id'] = item.id;
    return payload;
  }

  Future<CollectionItem?> restoreDeleted(CollectionChangeEvent event) async {
    if (event.action != 'deleted') return null;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final payload = Map<String, dynamic>.from(event.snapshot)
      ..remove('_previous_id')
      ..remove('id');
    payload['added_by'] = userId;

    final inserted = await Supabase.instance.client
        .from('collection_items')
        .insert(payload)
        .select()
        .single();

    final restored = CollectionItem.fromJson(inserted);
    await recordAdded(restored);

    // Retirer l'entrée delete restaurée.
    final events = await load(category: event.category);
    final kept = events.where((e) => e.id != event.id).toList();
    await _save(userId, event.category, kept);
    return restored;
  }
}
