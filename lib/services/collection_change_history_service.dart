import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/whereabouts_persistence.dart';

/// Entrée d'historique local (ajouts / suppressions / lieux / prêts).
class CollectionChangeEvent {
  final String id;
  /// added | deleted | location | loaned | returned
  final String action;
  final DateTime at;
  final CollectionCategory category;
  final String title;
  final String? imageUrl;
  final String? actorUsername;
  final String? detail;
  final Map<String, dynamic> snapshot;

  const CollectionChangeEvent({
    required this.id,
    required this.action,
    required this.at,
    required this.category,
    required this.title,
    required this.imageUrl,
    required this.snapshot,
    this.actorUsername,
    this.detail,
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
      actorUsername: json['actor_username']?.toString(),
      detail: json['detail']?.toString(),
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
        if (actorUsername != null) 'actor_username': actorUsername,
        if (detail != null) 'detail': detail,
        'snapshot': snapshot,
      };
}

/// Historique local (SharedPreferences) — TTL 90 jours, max 120 entrées.
///
/// Disparaît aussi si l'utilisateur efface les données du site / cookies
/// (stockage navigateur), change de profil, ou dépasse le TTL / max.
class CollectionChangeHistoryService {
  CollectionChangeHistoryService._();
  static final instance = CollectionChangeHistoryService._();

  static const _keyPrefix = 'collection_change_history_v1_';
  static const _seenPrefix = 'collection_modifs_seen_v1_';
  static const _ttl = Duration(days: 90);
  static const _maxEntries = 120;

  String _storageKey(String userId, CollectionCategory category) =>
      '$_keyPrefix${userId}_${category.dbValue}';

  String _seenKey(String userId, CollectionCategory category) =>
      '$_seenPrefix${userId}_${category.dbValue}';

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

  Future<bool> hasUnseen({required CollectionCategory category}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;
    final events = await load(category: category);
    if (events.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final seenRaw = prefs.getString(_seenKey(userId, category));
    final seenAt = DateTime.tryParse(seenRaw ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return events.any((e) => e.at.isAfter(seenAt));
  }

  Future<void> markSeen({required CollectionCategory category}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _seenKey(userId, category),
      DateTime.now().toIso8601String(),
    );
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

  Future<void> recordLocationChange({
    required CollectionItem item,
    required String fromLabel,
    required String toLabel,
  }) async {
    if (fromLabel.trim() == toLabel.trim()) return;
    await _record(
      action: 'location',
      item: item,
      detail: '📍 Lieu modifié : $fromLabel → $toLabel',
      snapshot: {
        'id': item.id,
        'from': fromLabel,
        'to': toLabel,
        'is_wishlist': item.isWishlist,
        'from_location': fromLabel,
        'to_location': toLabel,
      },
    );
  }

  Future<void> recordLoan({
    required CollectionItem item,
    required String borrower,
  }) async {
    await _record(
      action: 'loaned',
      item: item,
      detail: 'Prêté à $borrower',
      snapshot: {'id': item.id, 'borrower': borrower},
    );
  }

  Future<void> recordReturn({required CollectionItem item}) async {
    await _record(
      action: 'returned',
      item: item,
      detail: 'Objet rendu',
      snapshot: {'id': item.id},
    );
  }

  Future<void> recordPlay({
    required CollectionItem item,
    required String detail,
    DateTime? at,
  }) async {
    await _record(
      action: 'play',
      item: item,
      detail: detail,
      snapshot: {
        'id': item.id,
        'is_wishlist': false,
        'play': true,
      },
      at: at,
    );
  }

  /// Si l'historique local est vide : reconstituer ajouts récents + parties
  /// depuis la collection (évite l'écran « Aucune modification » trompeur).
  Future<List<CollectionChangeEvent>> loadWithBackfill({
    required CollectionCategory category,
  }) async {
    final existing = await load(category: category);
    if (existing.isNotEmpty) return existing;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const [];
    try {
      final rows = await Supabase.instance.client
          .from('collection_items')
          .select(
            'id, title, image_url, category, is_wishlist, created_at, metadata',
          )
          .eq('added_by', userId)
          .eq('category', category.dbValue)
          .order('created_at', ascending: false)
          .limit(40);
      final synthesized = <CollectionChangeEvent>[];
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final item = CollectionItem.fromJson(map);
        final created = DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now();
        synthesized.add(
          CollectionChangeEvent(
            id: 'backfill_add_${item.id}',
            action: 'added',
            at: created,
            category: category,
            title: item.title,
            imageUrl: item.imageUrl,
            snapshot: {
              'id': item.id,
              'is_wishlist': item.isWishlist,
            },
          ),
        );
        final plays = item.metadata?['boardgame_plays'];
        if (plays is List) {
          for (final p in plays) {
            if (p is! Map) continue;
            final date = DateTime.tryParse(p['date']?.toString() ?? '') ??
                created;
            final players = (p['players'] as List? ?? const [])
                .map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .join(', ');
            synthesized.add(
              CollectionChangeEvent(
                id: 'backfill_play_${item.id}_${p['share_id'] ?? date}',
                action: 'play',
                at: date,
                category: category,
                title: item.title,
                imageUrl: item.imageUrl,
                detail: players.isEmpty
                    ? 'Partie enregistrée'
                    : 'Partie · $players',
                snapshot: {
                  'id': item.id,
                  'is_wishlist': false,
                  'play': true,
                },
              ),
            );
          }
        }
      }
      synthesized.sort((a, b) => b.at.compareTo(a.at));
      final kept = synthesized.take(_maxEntries).toList();
      if (kept.isNotEmpty) {
        await _save(userId, category, kept);
      }
      return kept;
    } catch (_) {
      return existing;
    }
  }

  Future<void> _record({
    required String action,
    required CollectionItem item,
    required Map<String, dynamic> snapshot,
    String? detail,
    DateTime? at,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final events = await load(category: item.category);
    String? actor;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle();
      actor = row?['username']?.toString();
    } catch (_) {}
    final entry = CollectionChangeEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}_${item.id}',
      action: action,
      at: at ?? DateTime.now(),
      category: item.category,
      title: item.title,
      imageUrl: item.imageUrl,
      actorUsername: actor,
      detail: detail,
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

    final events = await load(category: event.category);
    final kept = events.where((e) => e.id != event.id).toList();
    await _save(userId, event.category, kept);
    return restored;
  }
}
