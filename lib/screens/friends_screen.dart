import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/profile_cache_service.dart';
import '../widgets/add_friend_sheet.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/friends_activity_feed.dart';
import '../widgets/households_sheet.dart';
import '../widgets/group_badge.dart';
import '../widgets/profile_avatar.dart';
import 'community_forum_screen.dart';
import 'exchanges_screen.dart';
import 'friend_collection_screen.dart';
import 'group_detail_screen.dart';
import 'groups_screen.dart';

const kAppPublicUrl = 'https://kiguelury.github.io/CollectionApp/';

/// Social : Activité · Amis & Groupes · Demandes.
class FriendsScreen extends StatefulWidget {
  final int initialTab;

  const FriendsScreen({super.key, this.initialTab = 0});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService();
  final _groupService = GroupService();
  final _filterController = TextEditingController();
  final _pseudoController = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  List<CollectionGroup> _groups = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];
  Map<String, ({int count, int common})> _summary = {};
  final Set<String> _busy = {};
  bool _loading = true;
  bool _sendingInvite = false;
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2);
    _filterController.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _filterController.removeListener(_applyFilter);
    _filterController.dispose();
    _pseudoController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    setState(() {
      _filtered = _service.filterFriends(_friends, _filterController.text);
    });
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.fetchFriends(force: force),
        _service.fetchIncomingFriendRequests(),
        _groupService.fetchMyGroups(force: force),
        _service.fetchOutgoingFriendRequests().catchError(
              (_) => <Map<String, dynamic>>[],
            ),
      ]);
      _friends = results[0] as List<Map<String, dynamic>>;
      _incoming = results[1] as List<Map<String, dynamic>>;
      _groups = results[2] as List<CollectionGroup>;
      _outgoing = results[3] as List<Map<String, dynamic>>;
      _applyFilter();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final ids = [
      for (final f in _friends)
        if (f['share_collections'] == true) f['profile_id'] as String,
    ];
    final s = await _service.fetchFriendsSummary(ids);
    if (mounted) setState(() => _summary = s);
  }

  Future<void> _openAddFriend() async {
    final added = await showAddFriendSheet(context);
    if (added == true) await _load(force: true);
  }

  void _openFriend(Map<String, dynamic> friend, {bool collection = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => FriendCollectionScreen(
          profileId: friend['profile_id'] as String,
          username: friend['username'] as String,
          avatarUrl: friend['avatar_url'] as String?,
          accentColor: friend['accent_color'] as String?,
          shareCollections: friend['share_collections'] as bool? ?? false,
          collectionView: collection,
        ),
      ),
    );
  }

  Future<void> _runRequest(
    Map<String, dynamic> req,
    Future<void> Function(String id) action,
    String success,
  ) async {
    final id = req['friendship_id'] as String;
    setState(() => _busy.add(id));
    try {
      await action(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success)),
        );
      }
      await _load(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _sendByPseudo() async {
    final pseudo = _pseudoController.text.trim();
    if (pseudo.isEmpty || _sendingInvite) return;
    setState(() => _sendingInvite = true);
    try {
      await _service.addFriendByUsername(pseudo);
      _pseudoController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demande envoyée à $pseudo')),
        );
      }
      await _load(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingInvite = false);
    }
  }

  Future<void> _copyInvite() async {
    final me = ProfileCacheService.instance.profile?.username;
    final text = me == null || me.isEmpty
        ? 'Rejoins-moi sur Paloma pour partager nos collections : $kAppPublicUrl'
        : 'Rejoins-moi sur Paloma pour partager nos collections ! '
            'Ajoute « $me » dans Social → Demandes. $kAppPublicUrl';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien d\'invitation copié')),
      );
    }
  }

  Future<void> _createGroup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupsScreen()),
    );
    if (mounted) await _load(force: true);
  }

  static const _wideBreakpoint = 950.0;

  @override
  Widget build(BuildContext context) {
    final pending = _incoming.length;
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final foyersAction = IconButton(
      icon: const Icon(Icons.home_work_outlined),
      tooltip: 'Foyers & lieux liés',
      onPressed: () => showHouseholdsSheet(context),
    );

    if (wide) {
      return Scaffold(
        appBar: AppAppBar(title: 'Social', actions: [foyersAction]),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: FriendsActivityFeed(compactChrome: true),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 340,
                    child: _buildDesktopSidebar(pending),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppAppBar(title: 'Social', actions: [foyersAction]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: _SocialPillBar(
              index: _tab,
              pending: pending,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                const FriendsActivityFeed(),
                _buildPeopleTab(),
                _buildRequestsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialShortcuts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityForumScreen()),
            ),
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: const Text('Forum'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExchangesScreen()),
            ),
            icon: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('Échanges'),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar(int pending) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _socialShortcuts(),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(
                'Demandes',
                count: pending,
                action: pending > 0
                    ? null
                    : TextButton(
                        onPressed: _openAddFriend,
                        child: const Text('Ajouter'),
                      ),
              ),
              if (_incoming.isEmpty && _outgoing.isEmpty)
                _emptyHint('Aucune demande en attente.')
              else ...[
                for (final r in _incoming.take(4)) _incomingRow(r),
                for (final r in _outgoing.take(2)) _outgoingRow(r),
                if (_incoming.length + _outgoing.length > 0)
                  TextButton(
                    onPressed: () => setState(() => _tab = 2),
                    child: const Text('Tout voir'),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionHeader(
          'Mes Groupes',
          count: _groups.length,
          action: TextButton.icon(
            onPressed: _createGroup,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Gérer'),
          ),
        ),
        if (_groups.isEmpty)
          _emptyHint('Aucun groupe pour l\'instant.')
        else
          for (final g in _groups) _groupRow(g),
        const SizedBox(height: 10),
        _sectionHeader(
          'Mes Amis',
          count: _friends.length,
          action: TextButton.icon(
            onPressed: _openAddFriend,
            icon: const Icon(Icons.person_add_alt_rounded, size: 18),
            label: const Text('Ajouter'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: TextField(
            controller: _filterController,
            decoration: InputDecoration(
              hintText: 'Chercher un ami…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_friends.isEmpty)
          _emptyHint('Ajoute des amis par pseudo.')
        else if (_filtered.isEmpty)
          _emptyHint('Aucun ami pour « ${_filterController.text} »')
        else
          for (final f in _filtered) _friendRow(f),
      ],
    );
  }

  // ── Amis & Groupes ─────────────────────────────────────────────────────

  Widget _buildPeopleTab() {
    if (_loading && _friends.isEmpty && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _socialShortcuts(),
          _sectionHeader(
            'Mes Groupes',
            count: _groups.length,
            action: TextButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Gérer'),
            ),
          ),
          if (_groups.isEmpty)
            _emptyHint(
              'Aucun groupe. Crée « Famille » ou « Colocs » pour partager '
              'une collection commune.',
            )
          else
            for (final g in _groups) _groupRow(g),
          const SizedBox(height: 14),
          _sectionHeader(
            'Mes Amis',
            count: _friends.length,
            action: TextButton.icon(
              onPressed: _openAddFriend,
              icon: const Icon(Icons.person_add_alt_rounded, size: 18),
              label: const Text('Ajouter'),
            ),
          ),
          if (_friends.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: TextField(
                controller: _filterController,
                decoration: InputDecoration(
                  hintText: 'Chercher un ami…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          if (_friends.isEmpty)
            _emptyHint(
              'Ajoute des amis par pseudo pour comparer vos collections et '
              'vous prêter des jeux.',
            )
          else if (_filtered.isEmpty)
            _emptyHint('Aucun ami pour « ${_filterController.text} »')
          else
            for (final f in _filtered) _friendRow(f),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {required int count, Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      );

  Widget _row({
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Widget menu,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            menu,
          ],
        ),
      ),
    );
  }

  Widget _groupRow(CollectionGroup g) {
    return _row(
      leading: GroupBadge.fromGroup(
        name: g.name,
        avatarUrl: g.avatarUrl,
        accentColor: g.accentColor,
        iconKey: g.iconKey,
        radius: 22,
      ),
      title: g.name,
      subtitle: 'Collection commune',
      onTap: () => _openGroup(g),
      menu: PopupMenuButton<String>(
        tooltip: 'Options',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (v) {
          if (v == 'open') _openGroup(g);
          if (v == 'manage') _createGroup();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('Ouvrir le groupe')),
          PopupMenuItem(
            value: 'manage',
            child: Text('Inviter / modifier / quitter'),
          ),
        ],
      ),
    );
  }

  Future<void> _openGroup(CollectionGroup g) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupDetailScreen(group: g)),
    );
  }

  Widget _friendRow(Map<String, dynamic> f) {
    final username = f['username'] as String? ?? 'Ami';
    final sharing = f['share_collections'] as bool? ?? false;
    final s = _summary[f['profile_id']];
    final subtitle = !sharing
        ? 'Collection non partagée'
        : s == null
            ? '…'
            : '${s.count} objet${s.count > 1 ? 's' : ''} · ${s.common} en commun';
    return _row(
      leading: ProfileAvatar(
        avatarUrl: f['avatar_url'] as String?,
        accentColorHex: f['accent_color'] as String?,
        fallbackInitial: username,
        radius: 22,
      ),
      title: username,
      subtitle: subtitle,
      onTap: () => _openFriend(f),
      menu: PopupMenuButton<String>(
        tooltip: 'Options',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (v) async {
          switch (v) {
            case 'profile':
              _openFriend(f);
            case 'collection':
              _openFriend(f, collection: true);
            case 'share':
              await _service.setShareCollections(
                f['friendship_id'] as String,
                !sharing,
              );
              await _load(force: true);
            case 'remove':
              await _confirmRemove(f);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'profile', child: Text('Voir le profil')),
          PopupMenuItem(
            value: 'collection',
            enabled: sharing,
            child: const Text('Voir sa collection'),
          ),
          PopupMenuItem(
            value: 'share',
            child: Text(
              sharing ? 'Arrêter le partage' : 'Partager nos collections',
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'remove',
            child: Text(
              'Retirer cet ami',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(Map<String, dynamic> friend) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Retirer cet ami ?'),
        content: Text(
          '« ${friend['username']} » ne sera plus dans ta liste d\'amis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _service.removeFriend(friend['friendship_id'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${friend['username']} retiré de tes amis')),
        );
      }
      await _load(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  // ── Demandes ───────────────────────────────────────────────────────────

  Widget _buildRequestsTab() {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ajouter un ami',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pseudoController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendByPseudo(),
                        decoration: const InputDecoration(
                          hintText: 'Pseudo exact',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sendingInvite ? null : _sendByPseudo,
                      child: _sendingInvite
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Envoyer'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _openAddFriend,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Rechercher'),
                    ),
                    TextButton.icon(
                      onPressed: _copyInvite,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Copier le lien d\'invitation'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionHeader('Reçues', count: _incoming.length),
          if (_incoming.isEmpty)
            _emptyHint('Aucune demande en attente.')
          else
            for (final r in _incoming) _incomingRow(r),
          const SizedBox(height: 12),
          _sectionHeader('Envoyées', count: _outgoing.length),
          if (_outgoing.isEmpty)
            _emptyHint('Aucune demande envoyée en attente.')
          else
            for (final r in _outgoing) _outgoingRow(r),
        ],
      ),
    );
  }

  Widget _requestAvatar(Map<String, dynamic> r) => ProfileAvatar(
        avatarUrl: r['avatar_url'] as String?,
        accentColorHex: r['accent_color'] as String?,
        fallbackInitial: r['username'] as String? ?? '?',
        radius: 22,
      );

  Widget _incomingRow(Map<String, dynamic> r) {
    final name = r['username'] as String? ?? 'Utilisateur';
    final busy = _busy.contains(r['friendship_id']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Row(
        children: [
          _requestAvatar(r),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            OutlinedButton(
              onPressed: () => _runRequest(
                r,
                _service.rejectFriendRequest,
                'Demande refusée',
              ),
              child: const Text('Refuser'),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: () => _runRequest(
                r,
                _service.acceptFriendRequest,
                '$name est maintenant ton ami',
              ),
              child: const Text('Accepter'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _outgoingRow(Map<String, dynamic> r) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busy.contains(r['friendship_id']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Row(
        children: [
          _requestAvatar(r),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['username'] as String? ?? 'Utilisateur',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'En attente',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: () => _runRequest(
                r,
                _service.cancelFriendRequest,
                'Demande annulée',
              ),
              child: const Text('Annuler'),
            ),
        ],
      ),
    );
  }
}

class _SocialPillBar extends StatelessWidget {
  final int index;
  final int pending;
  final ValueChanged<int> onChanged;

  const _SocialPillBar({
    required this.index,
    required this.pending,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = ['Flux', 'Amis & Groupes', 'Demandes'];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Material(
                  color: index == i
                      ? scheme.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => onChanged(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Badge(
                        isLabelVisible: i == 2 && pending > 0,
                        label: Text('$pending'),
                        offset: const Offset(10, -8),
                        child: Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                index == i ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
