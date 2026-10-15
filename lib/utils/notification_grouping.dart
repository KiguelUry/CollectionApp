import '../models/app_notification.dart';

/// À partir de combien de non-lues du même type on fusionne en une ligne.
const kNotificationGroupThreshold = 3;

/// Ligne du menu déroulant : une notification seule ou un groupe.
class NotificationRow {
  final AppNotificationType type;
  final List<AppNotification> items;
  final bool isGroup;

  const NotificationRow._(this.type, this.items, this.isGroup);

  factory NotificationRow.single(AppNotification n) =>
      NotificationRow._(n.type, [n], false);

  factory NotificationRow.group(
    AppNotificationType type,
    List<AppNotification> items,
  ) => NotificationRow._(type, List.unmodifiable(items), true);

  DateTime get latestAt =>
      items.map((n) => n.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);

  bool get hasUnread => items.any((n) => n.isUnread);

  int get count => items.length;

  String get title => isGroup
      ? groupedNotificationTitle(type, count)
      : notificationTitle(items.first);

  String? get subtitle => isGroup ? groupedSenderSummary(items) : null;
}

/// Regroupe les non-lues d'un même type dès [threshold] occurrences.
/// Les notifications lues / traitées restent toujours individuelles.
/// Résultat trié du plus récent au plus ancien.
List<NotificationRow> groupNotifications(
  Iterable<AppNotification> notifications, {
  int threshold = kNotificationGroupThreshold,
}) {
  final unreadByType = <AppNotificationType, List<AppNotification>>{};
  final rest = <AppNotification>[];
  for (final n in notifications) {
    if (n.isUnread) {
      unreadByType.putIfAbsent(n.type, () => []).add(n);
    } else {
      rest.add(n);
    }
  }

  final rows = <NotificationRow>[];
  for (final entry in unreadByType.entries) {
    final sorted = [...entry.value]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (sorted.length >= threshold) {
      rows.add(NotificationRow.group(entry.key, sorted));
    } else {
      rows.addAll(sorted.map(NotificationRow.single));
    }
  }
  rows.addAll(rest.map(NotificationRow.single));
  rows.sort((a, b) => b.latestAt.compareTo(a.latestAt));
  return rows;
}

int unreadNotificationCount(Iterable<AppNotification> notifications) =>
    notifications.where((n) => n.isUnread).length;

String groupedNotificationTitle(AppNotificationType type, int count) {
  switch (type) {
    case AppNotificationType.friendRequest:
      return '$count personnes vous ont demandé en ami';
    case AppNotificationType.groupInvite:
      return '$count invitations à rejoindre un groupe';
    case AppNotificationType.itemRecommendation:
      return '$count objets vous ont été recommandés';
    case AppNotificationType.playShared:
      return '$count parties ont été partagées avec vous';
  }
}

String notificationTitle(AppNotification n) {
  final who = n.senderName;
  switch (n.type) {
    case AppNotificationType.friendRequest:
      return '$who vous a demandé en ami';
    case AppNotificationType.groupInvite:
      final group = n.payload['group_name']?.toString().trim();
      return group == null || group.isEmpty
          ? '$who vous invite dans un groupe'
          : '$who vous invite dans le groupe « $group »';
    case AppNotificationType.itemRecommendation:
      final title = n.payload['title']?.toString().trim() ?? 'un objet';
      return '$who vous recommande « $title »';
    case AppNotificationType.playShared:
      final game = n.payload['game_title']?.toString().trim() ?? 'un jeu';
      return '$who a enregistré une partie de $game avec vous. '
          'Voulez-vous l\'ajouter à votre historique ?';
  }
}

/// « Alice, Bob et 4 autres ».
String groupedSenderSummary(List<AppNotification> items, {int maxNames = 2}) {
  final names = <String>[];
  final seen = <String>{};
  for (final n in items) {
    final name = n.senderName;
    if (seen.add(name.toLowerCase())) names.add(name);
  }
  if (names.length <= maxNames) {
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
  }
  final others = names.length - maxNames;
  return '${names.take(maxNames).join(', ')} et $others '
      '${others == 1 ? 'autre' : 'autres'}';
}
