import 'package:flutter/material.dart';

import '../services/group_service.dart';
import 'profile_avatar.dart';

Future<void> showGroupMembersSheet(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _GroupMembersSheet(
      groupId: groupId,
      groupName: groupName,
    ),
  );
}

class _GroupMembersSheet extends StatefulWidget {
  const _GroupMembersSheet({
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<_GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<_GroupMembersSheet> {
  final _groupService = GroupService();
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _members = await _groupService.fetchMembers(widget.groupId);
    } catch (_) {
      _members = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Membres · ${widget.groupName}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _members.isEmpty
                      ? const Center(child: Text('Aucun membre'))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 24, 24),
                          itemCount: _members.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final row = _members[index];
                            final profile = row['profiles'] as Map?;
                            final username =
                                profile?['username'] as String? ?? 'Membre';
                            return ListTile(
                              leading: ProfileAvatar(
                                avatarUrl: profile?['avatar_url'] as String?,
                                accentColorHex:
                                    profile?['accent_color'] as String?,
                                fallbackInitial: username,
                                radius: 22,
                              ),
                              title: Text(username),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
