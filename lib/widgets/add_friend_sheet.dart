import 'package:flutter/material.dart';
import '../services/friend_service.dart';
import '../utils/debounced_runner.dart';
import 'profile_avatar.dart';

/// Recherche globale + ajout d'un nouvel ami.
class AddFriendSheet extends StatefulWidget {
  const AddFriendSheet({super.key});

  @override
  State<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<AddFriendSheet> {
  final _service = FriendService();
  final _searchController = TextEditingController();
  final _debounce = DebouncedRunner();
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
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

  Future<void> _addFriend(String username) async {
    try {
      await _service.addFriendByUsername(username);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$username ajouté')),
      );
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ajouter un ami',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Chercher un pseudo…',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          if (_searchController.text.trim().isEmpty)
            Text(
              'Tape au moins une lettre pour trouver quelqu\'un.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            )
          else if (!_searching && _suggestions.isEmpty)
            Text(
              'Aucun profil trouvé.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = _suggestions[index];
                  final username = p['username'] as String;
                  final mutual = p['mutual_friends'] as int?;
                  return ListTile(
                    leading: ProfileAvatar(
                      avatarUrl: p['avatar_url'] as String?,
                      accentColorHex: p['accent_color'] as String?,
                      fallbackInitial: username,
                      radius: 22,
                    ),
                    title: Text(username),
                    subtitle: mutual != null && mutual > 0
                        ? Text(
                            '$mutual ami${mutual > 1 ? 's' : ''} en commun',
                          )
                        : null,
                    trailing: FilledButton.tonal(
                      onPressed: () => _addFriend(username),
                      child: const Text('Ajouter'),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool?> showAddFriendSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const AddFriendSheet(),
  );
}
