import 'package:flutter/material.dart';

import '../services/group_service.dart';

/// Pour un objet de groupe : « Chez Maman » plutôt qu'un lieu physique.
class GroupMemberLocationField extends StatefulWidget {
  const GroupMemberLocationField({
    super.key,
    required this.groupId,
    required this.selectedUserId,
    required this.onChanged,
  });

  final String groupId;
  final String? selectedUserId;
  final ValueChanged<({String? userId, String? username})> onChanged;

  @override
  State<GroupMemberLocationField> createState() =>
      _GroupMemberLocationFieldState();
}

class _GroupMemberLocationFieldState extends State<GroupMemberLocationField> {
  final _groupService = GroupService();
  List<({String id, String username})> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GroupMemberLocationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _groupService.fetchMembers(widget.groupId);
      _members = [
        for (final row in rows)
          (
            id: row['profile_id'] as String,
            username: (row['profiles'] as Map?)?['username'] as String? ??
                'Membre',
          ),
      ];
    } catch (_) {
      _members = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chez qui est l\'objet ?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: widget.selectedUserId,
          decoration: const InputDecoration(
            labelText: 'Membre du groupe',
            prefixIcon: Icon(Icons.person_pin_circle_outlined),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Non précisé'),
            ),
            ..._members.map(
              (m) => DropdownMenuItem(
                value: m.id,
                child: Text('Chez ${m.username}'),
              ),
            ),
          ],
          onChanged: (id) {
            if (id == null) {
              widget.onChanged((userId: null, username: null));
              return;
            }
            final m = _members.firstWhere((e) => e.id == id);
            widget.onChanged((userId: m.id, username: m.username));
          },
        ),
      ],
    );
  }
}
