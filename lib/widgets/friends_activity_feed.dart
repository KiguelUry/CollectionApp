import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_event.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../screens/item_detail_screen.dart';
import '../services/activity_service.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../utils/activity_feed_grouper.dart';
import '../utils/copy_friend_item.dart';
import 'collection_cover_image.dart';
import 'group_badge.dart';
import 'profile_avatar.dart';

/// Fil d'activité — digest par personne (pas de grosses cartes).
class FriendsActivityFeed extends StatefulWidget {
  const FriendsActivityFeed({super.key});

  @override
  State<FriendsActivityFeed> createState() => _FriendsActivityFeedState();
}

class _FriendsActivityFeedState extends State<FriendsActivityFeed> {
  final _service = ActivityService();
  final _friendService = FriendService();
  List<ActivityFeedGroup> _groups = [];
  List<_PersonDigest> _digests = [];
  bool _loading = true;
  String? _error;
  String? _addingItemId;
  Map<String, String> _reactions = {};
  Map<String, Map<String, int>> _reactionCounts = {};
  String? _focusActorId;
  String? _focusGroupId;
  List<CollectionGroup> _groupList = [];
  Map<String, Set<String>> _groupMembers = {};

  static const _emoji = ['🔥', '👏', '❤️', '🎲'];

  @override
  void initState() {
    super.initState();
    _load();
    _loadGroups();
  }

  Future<void> _loadReactions(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    final mine = await _service.fetchMyReactions(eventIds);
    final counts = await _service.fetchReactionCounts(eventIds);
    if (!mounted) return;
    if (mine.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('activity_reactions_v1');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          mine.addAll(decoded.map((k, v) => MapEntry('$k', '$v')));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _reactions = mine;
      _reactionCounts = counts;
    });
  }

  Future<void> _react(String eventId, String emoji) async {
    final next = Map<String, String>.from(_reactions);
    final remove = next[eventId] == emoji;
    if (remove) {
      next.remove(eventId);
    } else {
      next[eventId] = emoji;
    }
    setState(() => _reactions = next);
    try {
      await _service.setReaction(eventId, remove ? null : emoji);
      final counts = await _service.fetchReactionCounts([eventId]);
      if (mounted) {
        setState(() {
          _reactionCounts = {..._reactionCounts, ...counts};
          if (!counts.containsKey(eventId)) {
            _reactionCounts.remove(eventId);
          }
        });
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('activity_reactions_v1', jsonEncode(next));
    }
  }

  String _timeAgo(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'à l\'instant';
    if (d.inHours < 1) return 'il y a ${d.inMinutes} min';
    if (d.inDays < 1) return 'il y a ${d.inHours} h';
    if (d.inDays < 7) return 'il y a ${d.inDays} j';
    return '${at.day}/${at.month}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await _service.fetchFriendsFeed(limit: 80);
      _groups = groupActivityEvents(events);
      _digests = _buildDigests(_groups);
      final ids = [for (final group in _groups) group.head.id];
      unawaited(_loadReactions(ids));
    } catch (e) {
      _groups = [];
      _digests = [];
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  List<_PersonDigest> _buildDigests(List<ActivityFeedGroup> groups) {
    final order = <String>[];
    final map = <String, _PersonDigest>{};
    for (final g in groups) {
      final e = g.head;
      final existing = map[e.actorId];
      if (existing == null) {
        order.add(e.actorId);
        map[e.actorId] = _PersonDigest(
          actorId: e.actorId,
          username: e.actorUsername,
          avatarUrl: e.actorAvatarUrl,
          accentColor: e.actorAccentColor,
          groups: [g],
          latestAt: g.createdAt,
        );
      } else {
        existing.groups.add(g);
        if (g.createdAt.isAfter(existing.latestAt)) {
          existing.latestAt = g.createdAt;
        }
      }
    }
    return [for (final id in order) map[id]!];
  }

  bool _canAddFrom(ActivityEvent e) =>
      e.itemId != null && e.eventType != 'trophies_updated';

  Future<void> _addFromActivity(ActivityEvent e) async {
    final itemId = e.itemId;
    if (itemId == null) return;
    setState(() => _addingItemId = itemId);
    try {
      final item = await _friendService.fetchFriendItem(e.actorId, itemId);
      if (!mounted) return;
      if (item == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Objet introuvable ou collection non partagée'),
          ),
        );
        return;
      }
      await showCopyFriendItemSheet(
        context,
        source: item,
        friendUsername: e.actorUsername,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ajouter : $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingItemId = null);
    }
  }

  void _openGroup(ActivityFeedGroup group) {
    if (group.isBurst) {
      _showBurstDetail(group);
      return;
    }
    final e = group.head;
    if (e.itemId != null) {
      _openItem(e);
    } else if (_canAddFrom(e)) {
      _showSingleDetail(e);
    }
  }

  /// Ouvre la fiche de l'objet (lecture seule si c'est celui d'un ami).
  Future<void> _openItem(ActivityEvent e) async {
    final itemId = e.itemId;
    if (itemId == null) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    try {
      final item = await _friendService.fetchFriendItem(e.actorId, itemId);
      if (!mounted) return;
      if (item == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Objet introuvable ou collection non partagée'),
          ),
        );
        return;
      }
      final mine = e.actorId == me;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ItemDetailScreen(
            item: item,
            readOnly: !mine,
            friendUsername: mine ? null : e.actorUsername,
          ),
        ),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir : $err')),
        );
      }
    }
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await GroupService().fetchMyGroups();
      final members = <String, Set<String>>{};
      for (final g in groups) {
        final rows = await GroupService().fetchMembers(g.id);
        members[g.id] = {
          for (final r in rows)
            if (r['profile_id'] != null) r['profile_id'].toString()
            else if (r['id'] != null) r['id'].toString(),
        };
      }
      if (!mounted) return;
      setState(() {
        _groupList = groups;
        _groupMembers = members;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    if (_digests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 56),
            Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Rien pour l\'instant',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 8, 40, 0),
              child: Text(
                'Les ajouts, notes et coups de cœur de tes amis se regroupent ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final groupMembers =
        _focusGroupId == null ? null : _groupMembers[_focusGroupId];
    final visible = _digests.where((d) {
      if (_focusActorId != null) return d.actorId == _focusActorId;
      if (groupMembers != null) return groupMembers.contains(d.actorId);
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildPeopleStrip(scheme)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 18),
              itemBuilder: (context, i) => _buildDigest(visible[i], scheme),
            ),
          ),
        ],
      ),
    );
  }

  /// Une seule barre compacte : Tous · groupes · personnes (avatars 34 px).
  Widget _buildPeopleStrip(ColorScheme scheme) {
    final allSelected = _focusActorId == null && _focusGroupId == null;
    final chips = <Widget>[
      _StripChip(
        selected: allSelected,
        label: 'Tous',
        onTap: () => setState(() {
          _focusActorId = null;
          _focusGroupId = null;
        }),
        child: Icon(
          Icons.all_inclusive_rounded,
          size: 18,
          color: allSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
      for (final g in _groupList)
        _StripChip(
          selected: _focusGroupId == g.id,
          label: g.name,
          onTap: () => setState(() {
            _focusActorId = null;
            _focusGroupId = _focusGroupId == g.id ? null : g.id;
          }),
          child: GroupBadge(
            avatarUrl: g.avatarUrl,
            accentColorHex: g.accentColor,
            iconKey: g.iconKey,
            fallbackInitial: g.name,
            radius: 15,
          ),
        ),
      for (final d in _digests)
        _StripChip(
          selected: _focusActorId == d.actorId,
          label: d.username,
          onTap: () => setState(() {
            _focusGroupId = null;
            _focusActorId = _focusActorId == d.actorId ? null : d.actorId;
          }),
          child: ProfileAvatar(
            avatarUrl: d.avatarUrl,
            accentColorHex: d.accentColor,
            fallbackInitial: d.username,
            radius: 15,
          ),
        ),
    ];
    return SizedBox(
      height: 62,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => chips[i],
      ),
    );
  }

  Widget _buildDigest(_PersonDigest digest, ColorScheme scheme) {
    final accent = digest.accentColor != null
        ? ProfileAvatar.colorFromHex(digest.accentColor)
        : scheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProfileAvatar(
              avatarUrl: digest.avatarUrl,
              accentColorHex: digest.accentColor,
              fallbackInitial: digest.username,
              radius: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    digest.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${digest.groups.length} activité${digest.groups.length > 1 ? 's' : ''} · ${_timeAgo(digest.latestAt)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.55), width: 2.5),
            ),
          ),
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            children: [
              for (var i = 0; i < digest.groups.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 14,
                    thickness: 0.6,
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                _buildPulseLine(digest.groups[i], scheme),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPulseLine(ActivityFeedGroup group, ColorScheme scheme) {
    final e = group.head;
    final verb = switch (e.eventType) {
      'item_rated' => 'a noté',
      'wishlist_added' => 'wishlist',
      'trophies_updated' => 'trophées',
      'item_added' => group.isBurst ? 'a ajouté' : 'ajout',
      _ => 'activité',
    };
    final title = group.isBurst
        ? '${group.count} objets'
        : (e.itemTitle ?? 'un objet');

    return InkWell(
      onTap: () => _openGroup(group),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!group.isBurst &&
                e.itemImageUrl != null &&
                e.itemImageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 1),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    width: 26,
                    height: 34,
                    child: CollectionCoverImage(
                      url: e.itemImageUrl!,
                      width: 26,
                      height: 34,
                      bookCover: e.itemCategory == 'book',
                      fit: e.itemCategory == 'book'
                          ? BoxFit.contain
                          : BoxFit.cover,
                    ),
                  ),
                ),
              )
            else if (group.isBurst)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: _miniThumbs(group),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$verb  ',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (e.eventType == 'item_rated' && e.rating != null)
                          TextSpan(
                            text: '  ${e.rating}★',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber.shade700,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeAgo(group.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (final emoji in _emoji)
                        InkWell(
                          onTap: () => _react(e.id, emoji),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Opacity(
                              opacity: _reactions[e.id] == emoji ? 1 : 0.55,
                              child: Text(
                                (_reactionCounts[e.id]?[emoji] ?? 0) > 0
                                    ? '$emoji${_reactionCounts[e.id]![emoji]}'
                                    : emoji,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (_canAddFrom(e) && !group.isBurst) _addButton(e),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniThumbs(ActivityFeedGroup group) {
    final imgs = group.events
        .where((e) => e.itemImageUrl != null && e.itemImageUrl!.isNotEmpty)
        .take(3)
        .toList();
    if (imgs.isEmpty) {
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '+${group.count}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      );
    }
    return SizedBox(
      width: 46,
      height: 34,
      child: Stack(
        children: [
          for (var i = 0; i < imgs.length; i++)
            Positioned(
              left: i * 10.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 24,
                  height: 32,
                  child: CollectionCoverImage(
                    url: imgs[i].itemImageUrl!,
                    width: 24,
                    height: 32,
                    bookCover: imgs[i].itemCategory == 'book',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addButton(ActivityEvent e) {
    final loading = _addingItemId == e.itemId;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Ajouter',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: loading ? null : () => _addFromActivity(e),
      icon: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          : Icon(Icons.add_rounded, size: 18, color: scheme.primary),
    );
  }

  void _showSingleDetail(ActivityEvent e) {
    final scheme = Theme.of(context).colorScheme;
    CollectionCategory? cat;
    if (e.itemCategory != null) {
      try {
        cat = CollectionCategory.fromDbValue(e.itemCategory!);
      } catch (_) {}
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                e.description,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (e.itemImageUrl != null && e.itemImageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 40,
                        height: 52,
                        child: CollectionCoverImage(
                          url: e.itemImageUrl!,
                          width: 40,
                          height: 52,
                          bookCover: e.itemCategory == 'book',
                        ),
                      ),
                    )
                  else if (cat != null)
                    Icon(cat.icon, color: cat.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.itemTitle ?? 'Objet',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              if (_canAddFrom(e)) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addFromActivity(e);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter à ma collection'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showBurstDetail(ActivityFeedGroup group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scroll) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  group.summaryLabel(group.head),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: group.events.length,
                  itemBuilder: (context, i) {
                    final ev = group.events[i];
                    CollectionCategory? cat;
                    if (ev.itemCategory != null) {
                      try {
                        cat = CollectionCategory.fromDbValue(ev.itemCategory!);
                      } catch (_) {}
                    }
                    return ListTile(
                      leading: ev.itemImageUrl != null
                          ? SizedBox(
                              width: 40,
                              height: 52,
                              child: CollectionCoverImage(
                                url: ev.itemImageUrl!,
                                width: 40,
                                height: 52,
                                bookCover: ev.itemCategory == 'book',
                              ),
                            )
                          : Icon(
                              cat?.icon ?? Icons.inventory_2_outlined,
                              color: cat?.color ?? scheme.onSurfaceVariant,
                            ),
                      title: Text(
                        ev.itemTitle ?? 'Objet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      dense: true,
                      onTap: ev.itemId == null
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _openItem(ev);
                            },
                      trailing: _canAddFrom(ev) ? _addButton(ev) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonDigest {
  final String actorId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final List<ActivityFeedGroup> groups;
  DateTime latestAt;

  _PersonDigest({
    required this.actorId,
    required this.username,
    required this.avatarUrl,
    required this.accentColor,
    required this.groups,
    required this.latestAt,
  });
}

class _StripChip extends StatelessWidget {
  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback onTap;

  const _StripChip({
    required this.selected,
    required this.label,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 50,
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  border: Border.all(
                    color: selected
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.4),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: child,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
