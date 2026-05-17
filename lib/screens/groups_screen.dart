import 'package:flutter/material.dart';
import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../widgets/friend_picker_dialog.dart';
import '../widgets/main_drawer.dart';
import 'group_detail_screen.dart';

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
    await _groupService.createGroup(name);
    await _load();
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
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.groups, color: Colors.deepPurple),
                        title: Text(group.name),
                        subtitle: const Text('Voir la collection partagée'),
                        trailing: IconButton(
                          icon: const Icon(Icons.person_add),
                          onPressed: () => _addFriendToGroup(group),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => GroupDetailScreen(group: group),
                          ),
                        ).then((_) => _load()),
                      ),
                    );
                  },
                ),
    );
  }
}
