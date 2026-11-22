enum AppNotificationType {
  friendRequest('friend_request'),
  groupInvite('group_invite'),
  itemRecommendation('item_recommendation'),
  playShared('play_shared'),
  borrowRequest('borrow_request'),
  friendAccepted('friend_accepted'),
  activityReaction('activity_reaction');

  const AppNotificationType(this.dbValue);
  final String dbValue;

  static AppNotificationType? fromDb(String? raw) {
    for (final t in values) {
      if (t.dbValue == raw) return t;
    }
    return null;
  }
}

enum AppNotificationStatus {
  unread('unread'),
  read('read'),
  accepted('accepted'),
  declined('declined');

  const AppNotificationStatus(this.dbValue);
  final String dbValue;

  static AppNotificationStatus fromDb(String? raw) {
    for (final s in values) {
      if (s.dbValue == raw) return s;
    }
    return AppNotificationStatus.unread;
  }
}

class AppNotification {
  final String id;
  final String recipientId;
  final String? senderId;
  final AppNotificationType type;
  final Map<String, dynamic> payload;
  final AppNotificationStatus status;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.createdAt,
    this.senderId,
    this.payload = const {},
    this.status = AppNotificationStatus.unread,
  });

  /// `null` si le type est inconnu (migration future côté serveur).
  static AppNotification? tryFromJson(Map<String, dynamic> json) {
    var type = AppNotificationType.fromDb(json['type']?.toString());
    if (type == null) return null;
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : const <String, dynamic>{};
    // Repli client (migration pas encore jouée) : le vrai type est dans
    // `payload.kind` d'une recommandation.
    final kind = AppNotificationType.fromDb(payload['kind']?.toString());
    if (type == AppNotificationType.itemRecommendation && kind != null) {
      type = kind;
    }
    return AppNotification(
      id: json['id'].toString(),
      recipientId: json['recipient_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString(),
      type: type,
      payload: payload,
      status: AppNotificationStatus.fromDb(json['status']?.toString()),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isUnread => status == AppNotificationStatus.unread;

  /// Notification purement informative (pas de bouton accepter / refuser).
  bool get isInformational =>
      type == AppNotificationType.friendAccepted ||
      type == AppNotificationType.activityReaction;

  /// En attente d'une réponse (accepter / refuser).
  bool get isPending =>
      status == AppNotificationStatus.unread ||
      status == AppNotificationStatus.read;

  String get senderName {
    final raw = payload['sender_username']?.toString().trim();
    return raw == null || raw.isEmpty ? 'Quelqu\'un' : raw;
  }

  AppNotification copyWith({AppNotificationStatus? status}) {
    return AppNotification(
      id: id,
      recipientId: recipientId,
      senderId: senderId,
      type: type,
      payload: payload,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
