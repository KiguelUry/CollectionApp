import 'package:flutter/material.dart';
import '../services/friend_service.dart';
import '../widgets/add_friend_sheet.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/friends_activity_feed.dart';
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
  List<Map<String, dynamic>> _pendingRequests = [];
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
      final results = await Future.wait([
        _service.fetchFriends(),
        _service.fetchIncomingFriendRequests(),
      ]);
      _friends = results[0];
      _pendingRequests = results[1];
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => FriendCollectionScreen(
          profileId: friend['profile_id'] as String,
          username: friend['username'] as String,
          avatarUrl: friend['avatar_url'] as String?,
          accentColor: friend['accent_color'] as String?,
          shareCollections: friend['share_collections'] as bool? ?? false,
        ),
      ),
    );
  }

  Future<void> _acceptRequest(Map<String, dynamic> req) async {
    try {
      await _service.acceptFriendRequest(req['friendship_id'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${req['username'] ?? 'Ami'} est maintenant ton ami',
            ),
          ),
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

  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    try {
      await _service.rejectFriendRequest(req['friendship_id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Widget _buildFriendsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _filterController,
            decoration: InputDecoration(
              hintText: 'Chercher un ami…',
              border: InputBorder.none,
              icon: Icon(Icons.search, color: Colors.deepPurple.shade300),
              suffixIcon: _filterController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => _filterController.clear(),
                    )
                  : null,
            ),
          ),
        ),
        if (_pendingRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Icon(Icons.mail_outline, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text(
                  '${_pendingRequests.length} demande${_pendingRequests.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
          ..._pendingRequests.map(_buildRequestCard),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _loading
                ? 'Chargement…'
                : '${_filtered.length} ami${_filtered.length > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _friends.isEmpty && _pendingRequests.isEmpty
                  ? _buildEmpty()
                  : _friends.isNotEmpty && _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Aucun ami pour « ${_filterController.text} »',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              return _buildFriendCard(_filtered[index]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final accent = ProfileAvatar.colorFromHex(req['accent_color'] as String?);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: ProfileAvatar(
              avatarUrl: req['avatar_url'] as String?,
              accentColorHex: req['accent_color'] as String?,
              fallbackInitial: req['username'] as String? ?? '?',
              radius: 24,
            ),
            title: Text(
              req['username'] as String? ?? 'Utilisateur',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Veut rejoindre tes amis'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: Colors.red.shade400),
                  onPressed: () => _rejectRequest(req),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => _acceptRequest(req),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> f) {
    final username = f['username'] as String;
    final accent = ProfileAvatar.colorFromHex(f['accent_color'] as String?);
    final sharing = f['share_collections'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openFriend(f),
          onLongPress: () => _showFriendOptions(f),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  accent.withValues(alpha: 0.14),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  ProfileAvatar(
                    avatarUrl: f['avatar_url'] as String?,
                    accentColorHex: f['accent_color'] as String?,
                    fallbackInitial: username,
                    radius: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sharing
                              ? 'Collection partagée · appui long = options'
                              : 'Collections privées',
                          style: TextStyle(
                            fontSize: 12,
                            color: sharing
                                ? accent.withValues(alpha: 0.95)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: accent.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppAppBar(
          title: 'Amis',
          bottom: TabBar(
            indicatorColor: Colors.deepPurple.shade300,
            labelColor: Colors.deepPurple.shade800,
            tabs: const [
              Tab(icon: Icon(Icons.bolt_rounded, size: 20), text: 'Activité'),
              Tab(icon: Icon(Icons.people_rounded, size: 20), text: 'Mes amis'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Ajouter un ami',
              onPressed: _openAddFriend,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddFriend,
          icon: const Icon(Icons.person_add),
          label: const Text('Ami'),
        ),
        body: TabBarView(
          children: [
            const FriendsActivityFeed(),
            _buildFriendsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.people_outline_rounded, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text(
          'Construis ton cercle',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            'Ajoute des amis par pseudo pour voir leurs collections et '
            'copier des objets chez toi en un geste.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.35),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: _openAddFriend,
            icon: const Icon(Icons.person_add),
            label: const Text('Ajouter un ami'),
          ),
        ),
      ],
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
                'Permet de voir collection et wishlist mutuelles',
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
