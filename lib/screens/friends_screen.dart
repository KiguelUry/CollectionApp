import 'package:flutter/material.dart';
import '../services/friend_service.dart';
import '../utils/debounced_runner.dart';
import '../widgets/main_drawer.dart';
import '../widgets/profile_avatar.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService();
  final _usernameController = TextEditingController();
  final _debounce = DebouncedRunner();
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _usernameController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onSearchChanged);
    _usernameController.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _usernameController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _searching = false;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 300),
      action: () => _fetchSuggestions(query),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    final generation = ++_searchGeneration;
    setState(() => _searching = true);

    try {
      final results = await _service.searchProfiles(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _friends = await _service.fetchFriends();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addFriend(String username) async {
    try {
      await _service.addFriendByUsername(username);
      _usernameController.clear();
      setState(() => _suggestions = []);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$username ajouté')),
        );
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Amis')),
      drawer: const MainDrawer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Chercher un pseudo',
                hintText: 'Tape « pa » pour voir Papa…',
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.person_search),
              ),
            ),
          ),
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                elevation: 2,
                child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = _suggestions[index];
                  final username = p['username'] as String;
                  final mutual = p['mutual_friends'] as int?;
                  return ListTile(
                    dense: true,
                    leading: ProfileAvatar(
                      avatarUrl: p['avatar_url'] as String?,
                      accentColorHex: p['accent_color'] as String?,
                      fallbackInitial: username,
                      radius: 20,
                    ),
                    title: Text(username),
                    subtitle: mutual != null && mutual > 0
                        ? Text(
                            '$mutual ami${mutual > 1 ? 's' : ''} en commun',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.deepPurple.shade400,
                            ),
                          )
                        : null,
                    trailing: const Icon(Icons.add),
                    onTap: () => _addFriend(username),
                  );
                },
              ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Mes amis',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _friends.isEmpty
                    ? const Center(child: Text('Aucun ami pour l\'instant.'))
                    : ListView.builder(
                        itemCount: _friends.length,
                        itemBuilder: (context, index) {
                          final f = _friends[index];
                          return SwitchListTile(
                            secondary: ProfileAvatar(
                              avatarUrl: f['avatar_url'] as String?,
                              accentColorHex: f['accent_color'] as String?,
                              fallbackInitial: f['username'] as String,
                              radius: 22,
                            ),
                            title: Text(f['username'] as String),
                            subtitle: const Text('Partager mes collections'),
                            value: f['share_collections'] as bool? ?? true,
                            onChanged: (val) async {
                              await _service.setShareCollections(
                                f['friendship_id'] as String,
                                val,
                              );
                              await _load();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
