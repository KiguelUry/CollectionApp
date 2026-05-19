import 'package:flutter/material.dart';
import '../services/friend_service.dart';
import '../widgets/add_friend_sheet.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/profile_avatar.dart';
import 'friend_collection_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService();
  final _filterController = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _filterController.removeListener(_applyFilter);
    _filterController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    setState(() {
      _filtered = _service.filterFriends(_friends, _filterController.text);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _friends = await _service.fetchFriends();
      _applyFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openAddFriend() async {
    final added = await showAddFriendSheet(context);
    if (added == true) await _load();
  }

  void _openFriend(Map<String, dynamic> friend) {
    final sharing = friend['share_collections'] as bool? ?? false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => FriendCollectionScreen(
          profileId: friend['profile_id'] as String,
          username: friend['username'] as String,
          avatarUrl: friend['avatar_url'] as String?,
          accentColor: friend['accent_color'] as String?,
          shareCollections: sharing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Amis',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Ajouter un ami',
            onPressed: _openAddFriend,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddFriend,
        tooltip: 'Ajouter un ami',
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: 'Rechercher dans mes amis…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filterController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _filterController.clear(),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _loading
                  ? 'Chargement…'
                  : '${_filtered.length} ami${_filtered.length > 1 ? 's' : ''}'
                  '${_filterController.text.trim().isNotEmpty && _filtered.length != _friends.length ? ' sur ${_friends.length}' : ''}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _friends.isEmpty
                    ? _buildEmpty()
                    : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun ami ne correspond à « ${_filterController.text} »',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final f = _filtered[index];
                                final username = f['username'] as String;
                                final sharing =
                                    f['share_collections'] as bool? ?? false;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    leading: ProfileAvatar(
                                      avatarUrl: f['avatar_url'] as String?,
                                      accentColorHex:
                                          f['accent_color'] as String?,
                                      fallbackInitial: username,
                                      radius: 24,
                                    ),
                                    title: Text(username),
                                    subtitle: Text(
                                      sharing
                                          ? 'Collections partagées · Appuie pour voir'
                                          : 'Collection privée',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: sharing
                                            ? Colors.deepPurple.shade400
                                            : Colors.grey,
                                      ),
                                    ),
                                    trailing: Icon(
                                      sharing
                                          ? Icons.chevron_right
                                          : Icons.lock_outline,
                                      color: sharing
                                          ? Colors.deepPurple
                                          : Colors.grey,
                                    ),
                                    onTap: () => _openFriend(f),
                                    onLongPress: () => _showFriendOptions(f),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Aucun ami pour l\'instant',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Utilise le bouton + pour chercher quelqu\'un par pseudo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openAddFriend,
              icon: const Icon(Icons.person_add),
              label: const Text('Ajouter un ami'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFriendOptions(Map<String, dynamic> friend) {
    final sharing = friend['share_collections'] as bool? ?? false;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ProfileAvatar(
                avatarUrl: friend['avatar_url'] as String?,
                accentColorHex: friend['accent_color'] as String?,
                fallbackInitial: friend['username'] as String,
                radius: 22,
              ),
              title: Text(friend['username'] as String),
            ),
            SwitchListTile(
              title: const Text('Collections partagées'),
              subtitle: const Text(
                'Quand c\'est activé, vous pouvez voir vos collections respectives',
              ),
              value: sharing,
              onChanged: (val) async {
                Navigator.pop(ctx);
                await _service.setShareCollections(
                  friend['friendship_id'] as String,
                  val,
                );
                await _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('Voir la collection'),
              enabled: sharing,
              onTap: sharing
                  ? () {
                      Navigator.pop(ctx);
                      _openFriend(friend);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
