import 'package:flutter/material.dart';
import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/friend_picker_dialog.dart';
import '../widgets/group_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/group_members_sheet.dart';
import 'group_detail_screen.dart';
import 'group_edit_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _groupService = GroupService();
  final _friendService = FriendService();
  List<CollectionGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _groups = await _groupService.fetchMyGroups();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau groupe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom du groupe',
            hintText: 'Famille, colocs, club…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final group = await _groupService.createGroup(name);
    if (!mounted) return;
    await _openEdit(group);
    await _load();
  }

  Future<void> _openEdit(CollectionGroup group) async {
    final updated = await Navigator.push<CollectionGroup>(
      context,
      MaterialPageRoute(
        builder: (ctx) => GroupEditScreen(group: group),
      ),
    );
    if (updated != null && mounted) await _load();
  }

  Future<void> _addFriendToGroup(CollectionGroup group) async {
    final friends = await _friendService.fetchFriends();
    if (!mounted) return;
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute d\'abord des amis')),
      );
      return;
    }

    final picked = await showFriendPickerDialog(
      context: context,
      friends: friends,
    );
    if (picked == null) return;
    await _groupService.addMember(group.id, picked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membre ajouté au groupe')),
      );
    }
  }

  Future<void> _confirmDeleteGroup(CollectionGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le groupe ?'),
        content: Text(
          '« ${group.name} » sera supprimé. Les objets partagés '
          'resteront dans les collections mais ne seront plus liés à ce groupe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _groupService.deleteGroup(group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Groupe « ${group.name} » supprimé')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _openGroup(CollectionGroup group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => GroupDetailScreen(group: group),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Mes groupes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('Groupe'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      return _buildGroupCard(_groups[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 56),
        Icon(Icons.groups_rounded, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text(
          'Collection à plusieurs',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Crée un groupe « Famille » ou « Club jeux » pour partager '
            'des objets et voir qui possède quoi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.35),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: _createGroup,
            icon: const Icon(Icons.group_add),
            label: const Text('Créer un groupe'),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCard(CollectionGroup group) {
    final canEdit = _groupService.canEdit(group);
    final accent = ProfileAvatar.colorFromHex(group.accentColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openGroup(group),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.18),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  GroupBadge.fromGroup(
                    name: group.name,
                    avatarUrl: group.avatarUrl,
                    accentColor: group.accentColor,
                    iconKey: group.iconKey,
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          canEdit
                              ? 'Tu es créateur · collection partagée'
                              : 'Membre · collection partagée',
                          style: TextStyle(
                            fontSize: 12,
                            color: accent.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: accent),
                      onSelected: (value) {
                        switch (value) {
                          case 'members':
                            showGroupMembersSheet(
                              context,
                              groupId: group.id,
                              groupName: group.name,
                            );
                          case 'edit':
                            _openEdit(group);
                          case 'delete':
                            _confirmDeleteGroup(group);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'members',
                          child: Text('Membres'),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Personnaliser'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Supprimer',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.people_outline, color: accent),
                      tooltip: 'Membres',
                      onPressed: () => showGroupMembersSheet(
                        context,
                        groupId: group.id,
                        groupName: group.name,
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.person_add_alt_1, color: accent),
                    tooltip: 'Inviter',
                    onPressed: () => _addFriendToGroup(group),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
