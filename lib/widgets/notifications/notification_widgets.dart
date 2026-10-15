import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_notification.dart';
import '../../utils/notification_grouping.dart';

IconData notificationTypeIcon(AppNotificationType type) {
  switch (type) {
    case AppNotificationType.friendRequest:
      return Icons.person_add_alt_1_rounded;
    case AppNotificationType.groupInvite:
      return Icons.group_add_rounded;
    case AppNotificationType.itemRecommendation:
      return Icons.card_giftcard_rounded;
    case AppNotificationType.playShared:
      return Icons.casino_rounded;
  }
}

String notificationAcceptLabel(AppNotificationType type) {
  switch (type) {
    case AppNotificationType.friendRequest:
      return 'Accepter';
    case AppNotificationType.groupInvite:
      return 'Rejoindre';
    case AppNotificationType.itemRecommendation:
      return 'Ajouter à ma wishlist';
    case AppNotificationType.playShared:
      return 'Ajouter à mon historique';
  }
}

String notificationDeclineLabel(AppNotificationType type) =>
    type == AppNotificationType.friendRequest ||
        type == AppNotificationType.groupInvite
    ? 'Refuser'
    : 'Ignorer';

String _relativeTime(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'à l\'instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  if (d.inDays < 7) return 'il y a ${d.inDays} j';
  return DateFormat('d MMM', 'fr_FR').format(at);
}

/// Cloche + pastille du nombre de non-lues.
class NotificationBellButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback? onPressed;

  const NotificationBellButton({
    super.key,
    required this.unreadCount,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final label = unreadCount > 99 ? '99+' : '$unreadCount';
    return IconButton(
      key: const ValueKey('notification_bell'),
      tooltip: 'Notifications',
      onPressed: onPressed,
      icon: Badge(
        key: const ValueKey('notification_badge'),
        isLabelVisible: unreadCount > 0,
        label: Text(label),
        child: Icon(
          unreadCount > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
        ),
      ),
    );
  }
}

/// Contenu du menu déroulant (lignes groupées style Facebook).
class NotificationDropdownPanel extends StatelessWidget {
  final List<NotificationRow> rows;
  final ValueChanged<NotificationRow> onRowTap;
  final VoidCallback? onMarkAllRead;
  final bool loading;
  final DateTime? now;

  const NotificationDropdownPanel({
    super.key,
    required this.rows,
    required this.onRowTap,
    this.onMarkAllRead,
    this.loading = false,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = rows.any((r) => r.hasUnread);
    final at = now ?? DateTime.now();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasUnread && onMarkAllRead != null)
                  TextButton(
                    key: const ValueKey('notification_mark_all_read'),
                    onPressed: onMarkAllRead,
                    child: const Text('Tout marquer lu'),
                  ),
              ],
            ),
          ),
          if (loading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Aucune notification pour le moment',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  return _NotificationRowTile(
                    key: ValueKey(
                      row.isGroup
                          ? 'notification_group_${row.type.dbValue}'
                          : 'notification_${row.items.first.id}',
                    ),
                    row: row,
                    timeLabel: _relativeTime(row.latestAt, at),
                    onTap: () => onRowTap(row),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationRowTile extends StatelessWidget {
  final NotificationRow row;
  final String timeLabel;
  final VoidCallback onTap;

  const _NotificationRowTile({
    super.key,
    required this.row,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = row.hasUnread;
    final subtitle = row.subtitle;
    return Material(
      color: unread
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Badge(
          isLabelVisible: row.isGroup,
          label: Text('${row.count}'),
          child: CircleAvatar(
            backgroundColor: scheme.secondaryContainer,
            child: Icon(
              notificationTypeIcon(row.type),
              color: scheme.onSecondaryContainer,
              size: 20,
            ),
          ),
        ),
        title: Text(
          row.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle == null || subtitle.isEmpty
              ? timeLabel
              : '$subtitle · $timeLabel',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: unread
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              )
            : null,
      ),
    );
  }
}

/// Vue détaillée (groupe ou notification seule) avec accepter / refuser.
class NotificationDetailView extends StatelessWidget {
  final List<AppNotification> notifications;
  final Future<void> Function(AppNotification n) onAccept;
  final Future<void> Function(AppNotification n) onDecline;
  final Set<String> busyIds;
  final VoidCallback? onAcceptAll;

  const NotificationDetailView({
    super.key,
    required this.notifications,
    required this.onAccept,
    required this.onDecline,
    this.busyIds = const {},
    this.onAcceptAll,
  });

  @override
  Widget build(BuildContext context) {
    final pending = notifications.where((n) => n.isPending).length;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (onAcceptAll != null && pending > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FilledButton.tonalIcon(
              key: const ValueKey('notification_accept_all'),
              onPressed: busyIds.isEmpty ? onAcceptAll : null,
              icon: const Icon(Icons.done_all_rounded),
              label: Text('Tout accepter ($pending)'),
            ),
          ),
        for (final n in notifications)
          _NotificationActionCard(
            key: ValueKey('notification_card_${n.id}'),
            notification: n,
            busy: busyIds.contains(n.id),
            onAccept: () => onAccept(n),
            onDecline: () => onDecline(n),
          ),
      ],
    );
  }
}

class _NotificationActionCard extends StatelessWidget {
  final AppNotification notification;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _NotificationActionCard({
    super.key,
    required this.notification,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final scheme = Theme.of(context).colorScheme;
    final image = n.payload['image_url']?.toString();
    final message = n.payload['message']?.toString();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundImage: image != null && image.startsWith('http')
                      ? NetworkImage(image)
                      : null,
                  child: Icon(
                    notificationTypeIcon(n.type),
                    color: scheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notificationTitle(n),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (message != null && message.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '« $message »',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (busy)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            else if (n.isPending)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    key: ValueKey('notification_decline_${n.id}'),
                    onPressed: onDecline,
                    child: Text(notificationDeclineLabel(n.type)),
                  ),
                  FilledButton(
                    key: ValueKey('notification_accept_${n.id}'),
                    onPressed: onAccept,
                    child: Text(notificationAcceptLabel(n.type)),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  avatar: Icon(
                    n.status == AppNotificationStatus.accepted
                        ? Icons.check_circle_rounded
                        : Icons.cancel_outlined,
                    size: 18,
                  ),
                  label: Text(
                    n.status == AppNotificationStatus.accepted
                        ? 'Accepté'
                        : 'Refusé',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
