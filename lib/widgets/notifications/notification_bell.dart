import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/notification_detail_screen.dart';
import '../../services/notification_service.dart';
import '../../utils/notification_grouping.dart';
import 'notification_widgets.dart';

/// Cloche du header principal : badge + menu déroulant groupé.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _service = NotificationService.instance;
  final _menu = MenuController();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    if (Supabase.instance.client.auth.currentUser != null) _service.attach();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _service.detach();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openRow(NotificationRow row) async {
    _menu.close();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotificationDetailScreen(row: row)),
    );
    await _service.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(-300, 0),
      menuChildren: [
        SizedBox(
          width: 360,
          child: NotificationDropdownPanel(
            rows: _service.rows,
            loading: _service.loading,
            onRowTap: _openRow,
            onMarkAllRead: _service.markAllRead,
          ),
        ),
      ],
      builder: (context, controller, _) => NotificationBellButton(
        unreadCount: _service.unreadCount,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            _service.refresh();
            controller.open();
          }
        },
      ),
    );
  }
}
