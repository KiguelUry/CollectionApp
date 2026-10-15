import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../utils/item_recommendation.dart';
import '../utils/notification_grouping.dart';
import '../utils/wishlist_promote.dart';
import 'collection_refresh.dart';
import 'friend_service.dart';
import 'play_share_service.dart';
import 'profile_cache_service.dart';

/// Centre de notifications (table `app_notifications`).
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final instance = NotificationService._();

  static const _table = 'app_notifications';
  static const _pollInterval = Duration(seconds: 60);
  static const _fetchLimit = 80;

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  List<AppNotification> _items = [];
  bool _loading = false;
  Timer? _poll;
  int _listeners = 0;

  List<AppNotification> get notifications => List.unmodifiable(_items);
  List<NotificationRow> get rows => groupNotifications(_items);
  int get unreadCount => unreadNotificationCount(_items);
  bool get loading => _loading;

  /// Démarre le rafraîchissement périodique (cloche visible).
  void attach() {
    _listeners++;
    if (_listeners == 1) {
      unawaited(refresh());
      _poll = Timer.periodic(_pollInterval, (_) => refresh());
    }
  }

  void detach() {
    _listeners = (_listeners - 1).clamp(0, 1 << 20);
    if (_listeners == 0) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> refresh() async {
    final uid = _userId;
    if (uid == null || _loading) return;
    _loading = true;
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(_fetchLimit);
      _items = [
        for (final r in rows as List)
          ?AppNotification.tryFromJson(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e) {
      // Table absente (migration non jouée) : centre vide, pas de crash.
      if (kDebugMode) debugPrint('Notifications: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _replaceLocal(Iterable<String> ids, AppNotificationStatus status) {
    final set = ids.toSet();
    _items = [
      for (final n in _items)
        set.contains(n.id) ? n.copyWith(status: status) : n,
    ];
    notifyListeners();
  }

  Future<void> _setStatus(
    Iterable<String> ids,
    AppNotificationStatus status,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    _replaceLocal(list, status);
    await _client
        .from(_table)
        .update({
          'status': status.dbValue,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .inFilter('id', list);
  }

  /// Marque comme vues (sans répondre) les notifications non lues.
  Future<void> markRead(Iterable<AppNotification> items) async {
    final ids = items.where((n) => n.isUnread).map((n) => n.id);
    try {
      await _setStatus(ids, AppNotificationStatus.read);
    } catch (e) {
      if (kDebugMode) debugPrint('Notifications markRead: $e');
    }
  }

  Future<void> markAllRead() => markRead(_items);

  /// Envoi client (recommandation, invitation groupe, partie partagée).
  /// Les doublons ([dedupeKey]) sont ignorés silencieusement, sauf si
  /// [replaceExisting] : l'ancienne notification envoyée est remplacée
  /// (ex. réinviter après un refus).
  Future<void> send({
    required String recipientId,
    required AppNotificationType type,
    required Map<String, dynamic> payload,
    String? dedupeKey,
    bool replaceExisting = false,
  }) async {
    final uid = _userId;
    if (uid == null || recipientId == uid) return;
    if (replaceExisting && dedupeKey != null) {
      await _client
          .from(_table)
          .delete()
          .eq('recipient_id', recipientId)
          .eq('sender_id', uid)
          .eq('dedupe_key', dedupeKey);
    }
    final row = {
      'recipient_id': recipientId,
      'sender_id': uid,
      'type': type.dbValue,
      'payload': {
        'sender_username': ProfileCacheService.instance.profile?.username,
        ...payload,
      },
      'dedupe_key': ?dedupeKey,
    };
    try {
      await _client.from(_table).insert(row);
    } on PostgrestException catch (e) {
      // 23505 = déjà envoyée (dedupe_key).
      if (e.code != '23505') rethrow;
    }
  }

  /// Accepte : retourne un message à afficher.
  Future<String> accept(AppNotification n) async {
    late final String message;
    switch (n.type) {
      case AppNotificationType.friendRequest:
        final friendshipId = n.payload['friendship_id']?.toString();
        if (friendshipId == null) throw Exception('Demande introuvable');
        await FriendService().acceptFriendRequest(friendshipId);
        message = '${n.senderName} fait maintenant partie de tes amis';
      case AppNotificationType.groupInvite:
        await _client.rpc(
          'accept_group_invite',
          params: {'p_notification_id': n.id},
        );
        _replaceLocal([n.id], AppNotificationStatus.accepted);
        return 'Tu as rejoint le groupe';
      case AppNotificationType.itemRecommendation:
        message = await _addRecommendationToWishlist(n);
      case AppNotificationType.playShared:
        message = await PlayShareService.instance.importSharedPlay(n.payload);
    }
    await _setStatus([n.id], AppNotificationStatus.accepted);
    return message;
  }

  Future<String> decline(AppNotification n) async {
    if (n.type == AppNotificationType.friendRequest) {
      final friendshipId = n.payload['friendship_id']?.toString();
      if (friendshipId != null) {
        await FriendService().rejectFriendRequest(friendshipId);
      }
    }
    await _setStatus([n.id], AppNotificationStatus.declined);
    return 'Refusé';
  }

  Future<String> _addRecommendationToWishlist(AppNotification n) async {
    final uid = _userId;
    if (uid == null) throw Exception('Non connecté');
    final draft = wishlistDraftFromRecommendation(n.payload, userId: uid);
    if (draft == null) throw Exception('Recommandation invalide');

    for (final wishlist in [true, false]) {
      final existing = await findDuplicateRow(
        title: draft.title,
        categoryDb: draft.category.dbValue,
        isWishlist: wishlist,
        subcategory: draft.subcategory,
      );
      if (existing != null) {
        return wishlist
            ? '« ${draft.title} » est déjà dans ta wishlist'
            : 'Tu possèdes déjà « ${draft.title} »';
      }
    }

    await _client
        .from('collection_items')
        .insert(draft.toInsertJson(isWishlist: true, addedBy: uid));
    CollectionRefresh.instance.bump();
    return '« ${draft.title} » ajouté à ta wishlist';
  }

  @visibleForTesting
  void debugSetItems(List<AppNotification> items) {
    _items = items;
    notifyListeners();
  }
}
