import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../utils/notification_grouping.dart';
import '../widgets/notifications/notification_widgets.dart';

/// Détail d'une ligne du centre de notifications (groupe ou seule).
class NotificationDetailScreen extends StatefulWidget {
  final NotificationRow row;

  const NotificationDetailScreen({super.key, required this.row});

  @override
  State<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  final _service = NotificationService.instance;
  late List<AppNotification> _items = List.of(widget.row.items);
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _service.markRead(_items);
  }

  void _setStatus(String id, AppNotificationStatus status) {
    _items = [
      for (final n in _items) n.id == id ? n.copyWith(status: status) : n,
    ];
  }

  Future<void> _run(
    AppNotification n,
    Future<String> Function(AppNotification) action,
    AppNotificationStatus onSuccess, {
    bool showSnack = true,
  }) async {
    setState(() => _busy.add(n.id));
    try {
      final message = await action(n);
      if (!mounted) return;
      setState(() => _setStatus(n.id, onSuccess));
      if (showSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Action impossible : $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  Future<void> _acceptAll() async {
    final pending = _items.where((n) => n.isPending).toList();
    for (final n in pending) {
      await _run(
        n,
        _service.accept,
        AppNotificationStatus.accepted,
        showSnack: false,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pending.length} notifications acceptées')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          row.isGroup
              ? groupedNotificationTitle(row.type, row.count)
              : 'Notification',
          maxLines: 2,
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: NotificationDetailView(
            notifications: _items,
            busyIds: _busy,
            onAccept: (n) =>
                _run(n, _service.accept, AppNotificationStatus.accepted),
            onDecline: (n) =>
                _run(n, _service.decline, AppNotificationStatus.declined),
            onAcceptAll: row.isGroup ? _acceptAll : null,
          ),
        ),
      ),
    );
  }
}
