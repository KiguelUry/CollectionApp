import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _members = await _groupService.fetchMembers(widget.groupId);
    } catch (_) {
      _members = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirmRemove(Map<String, dynamic> row) async {
    final profile = row['profiles'] as Map?;
    final profileId = row['profile_id'] as String?;
    final username = profile?['username'] as String? ?? 'Membre';
    if (profileId == null) return;

    final isSelf = profileId == _currentUserId;
    final canManage = await _groupService
        .fetchGroup(widget.groupId)
        .then((g) => _groupService.canEdit(g));

    if (!isSelf && !canManage) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSelf ? 'Quitter le groupe ?' : 'Retirer ce membre ?'),
        content: Text(
          isSelf
              ? 'Tu ne verras plus la collection partagée de « ${widget.groupName} ».'
              : 'Retirer « $username » du groupe « ${widget.groupName} » ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: isSelf
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSelf ? 'Quitter' : 'Retirer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _groupService.removeMember(widget.groupId, profileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSelf ? 'Tu as quitté le groupe' : '$username retiré du groupe',
          ),
        ),
      );
      if (isSelf) {
        Navigator.pop(context);
        Navigator.pop(context);
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
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
                      : FutureBuilder(
                          future: _groupService.fetchGroup(widget.groupId),
                          builder: (context, snap) {
                            final canEdit = snap.hasData
                                ? _groupService.canEdit(snap.data!)
                                : false;
                            return ListView.separated(
                              controller: scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: _members.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final row = _members[index];
                                final profile = row['profiles'] as Map?;
                                final profileId =
                                    row['profile_id'] as String?;
                                final username = profile?['username']
                                        as String? ??
                                    'Membre';
                                final isSelf =
                                    profileId == _currentUserId;
                                final canRemove =
                                    isSelf || canEdit;

                                return ListTile(
                                  leading: ProfileAvatar(
                                    avatarUrl:
                                        profile?['avatar_url'] as String?,
                                    accentColorHex:
                                        profile?['accent_color'] as String?,
                                    fallbackInitial: username,
                                    radius: 22,
                                  ),
                                  title: Text(username),
                                  subtitle: isSelf
                                      ? const Text('Toi')
                                      : null,
                                  trailing: canRemove
                                      ? IconButton(
                                          icon: Icon(
                                            isSelf
                                                ? Icons.logout
                                                : Icons.person_remove_outlined,
                                            color: isSelf
                                                ? null
                                                : Colors.red.shade400,
                                          ),
                                          tooltip: isSelf
                                              ? 'Quitter le groupe'
                                              : 'Retirer du groupe',
                                          onPressed: () =>
                                              _confirmRemove(row),
                                        )
                                      : null,
                                );
                              },
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
