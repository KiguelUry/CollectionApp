enum AppNotificationType {
  friendRequest('friend_request'),
  groupInvite('group_invite'),
  itemRecommendation('item_recommendation'),
  playShared('play_shared');

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
    final type = AppNotificationType.fromDb(json['type']?.toString());
    if (type == null) return null;
    final rawPayload = json['payload'];
    return AppNotification(
      id: json['id'].toString(),
      recipientId: json['recipient_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString(),
      type: type,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
      status: AppNotificationStatus.fromDb(json['status']?.toString()),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isUnread => status == AppNotificationStatus.unread;

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
