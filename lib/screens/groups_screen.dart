import 'package:flutter/material.dart';
import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../widgets/friend_picker_dialog.dart';
import '../widgets/group_badge.dart';
import '../widgets/main_drawer.dart';
import '../widgets/profile_avatar.dart';
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
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'ex: Famille',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
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
      appBar: AppBar(title: const Text('Mes groupes')),
      drawer: const MainDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGroup,
        child: const Icon(Icons.group_add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(
                  child: Text(
                    'Crée un groupe « Famille » pour partager des objets.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final canEdit = _groupService.canEdit(group);
                    final accent =
                        ProfileAvatar.colorFromHex(group.accentColor);

                    return Card(
                      child: ListTile(
                        leading: GroupBadge.fromGroup(
                          name: group.name,
                          avatarUrl: group.avatarUrl,
                          accentColor: group.accentColor,
                          iconKey: group.iconKey,
                          radius: 26,
                        ),
                        title: Text(group.name),
                        subtitle: Text(
                          canEdit
                              ? 'Collection partagée · Personnalisable'
                              : 'Collection partagée',
                          style: TextStyle(
                            fontSize: 12,
                            color: accent.withValues(alpha: 0.9),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canEdit)
                              IconButton(
                                icon: const Icon(Icons.palette_outlined),
                                tooltip: 'Personnaliser',
                                onPressed: () => _openEdit(group),
                              ),
                            IconButton(
                              icon: const Icon(Icons.person_add),
                              tooltip: 'Ajouter un membre',
                              onPressed: () => _addFriendToGroup(group),
                            ),
                          ],
                        ),
                        onTap: () => _openGroup(group),
                        onLongPress:
                            canEdit ? () => _openEdit(group) : null,
                      ),
                    );
                  },
                ),
    );
  }
}
