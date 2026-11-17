import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_event.dart';
import '../models/collection_category.dart';
import '../services/activity_service.dart';
import '../services/friend_service.dart';
import '../utils/activity_feed_grouper.dart';
import '../utils/copy_friend_item.dart';
import 'collection_cover_image.dart';
import 'profile_avatar.dart';

/// Fil d'activité des amis (ajouts regroupés, notes, trophées).
/// Layout compact type timeline — pas de grosses cartes.
class FriendsActivityFeed extends StatefulWidget {
  const FriendsActivityFeed({super.key});

  @override
  State<FriendsActivityFeed> createState() => _FriendsActivityFeedState();
}

class _FriendsActivityFeedState extends State<FriendsActivityFeed> {
  final _service = ActivityService();
  final _friendService = FriendService();
  List<ActivityFeedGroup> _groups = [];
  bool _loading = true;
  String? _error;
  String? _addingItemId;
  Map<String, String> _reactions = {};
  Map<String, Map<String, int>> _reactionCounts = {};

  static const _emoji = ['🔥', '👏', '❤️', '🎲'];

  @override
  void initState() {
    super.initState();
    _load();
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
    if (d.inMinutes < 1) return 'À l\'instant';
    if (d.inHours < 1) return 'Il y a ${d.inMinutes} min';
    if (d.inDays < 1) return 'Il y a ${d.inHours} h';
    if (d.inDays < 7) return 'Il y a ${d.inDays} j';
    return '${at.day}/${at.month}/${at.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await _service.fetchFriendsFeed(limit: 80);
      _groups = groupActivityEvents(events);
      final ids = [
        for (final group in _groups) group.head.id,
      ];
      unawaited(_loadReactions(ids));
    } catch (e) {
      _groups = [];
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'wishlist_added' => Icons.favorite_rounded,
      'item_rated' => Icons.star_rounded,
      'trophies_updated' => Icons.emoji_events_rounded,
      _ => Icons.add_circle_rounded,
    };
  }

  Color _iconColorFor(String type) {
    return switch (type) {
      'wishlist_added' => Colors.pink.shade400,
      'item_rated' => Colors.amber.shade700,
      'trophies_updated' => Colors.orange.shade700,
      _ => Colors.teal.shade600,
    };
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

  void _openActivityDetail(ActivityFeedGroup group) {
    if (group.isBurst) {
      _showBurstDetail(group);
      return;
    }
    final e = group.head;
    if (!_canAddFrom(e)) return;
    _showSingleDetail(e);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
    final scheme = Theme.of(context).colorScheme;
    if (_groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            Icon(
              Icons.dynamic_feed_rounded,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'Le fil est calme…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                'Tes ajouts et ceux de tes amis apparaissent ici — '
                'tu peux déjà réagir avec 🔥 👏 ❤️ 🎲.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        itemCount: _groups.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 0.6,
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        itemBuilder: (context, index) => _buildRow(_groups[index]),
      ),
    );
  }

  Widget _buildRow(ActivityFeedGroup group) {
    final e = group.head;
    final scheme = Theme.of(context).colorScheme;
    final iconColor = _iconColorFor(e.eventType);

    return InkWell(
      onTap: () => _openActivityDetail(group),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(
              avatarUrl: e.actorAvatarUrl,
              accentColorHex: e.actorAccentColor,
              fallbackInitial: e.actorUsername,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: group.summaryLabel(e),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  height: 1.25,
                                  color: scheme.onSurface,
                                ),
                              ),
                              TextSpan(
                                text: '  ·  ${_timeAgo(group.createdAt)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Icon(_iconFor(e.eventType), size: 16, color: iconColor),
                    ],
                  ),
                  if (group.isBurst) ...[
                    const SizedBox(height: 8),
                    _buildThumbnailStrip(group),
                  ] else if (e.itemTitle != null) ...[
                    const SizedBox(height: 6),
                    _buildSinglePreview(e),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final emoji in _emoji)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _react(e.id, emoji),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Opacity(
                                opacity: _reactions[e.id] == emoji ? 1 : 0.7,
                                child: Text(
                                  (_reactionCounts[e.id]?[emoji] ?? 0) > 0
                                      ? '$emoji ${_reactionCounts[e.id]![emoji]}'
                                      : emoji,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _reactions[e.id] == emoji
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (_canAddFrom(e)) _addButton(e),
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

  Widget _buildThumbnailStrip(ActivityFeedGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final withImage = group.events
        .where((e) => e.itemImageUrl != null && e.itemImageUrl!.isNotEmpty)
        .take(6)
        .toList();

    return Row(
      children: [
        if (withImage.isEmpty)
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+${group.count}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              scrollDirection: Axis.horizontal,
              itemCount: withImage.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final ev = withImage[i];
                return _thumb(ev.itemImageUrl!, ev.itemCategory);
              },
            ),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Voir le détail · ${group.count} éléments',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _thumb(String url, String? categoryDb) {
    final isBook = categoryDb == 'book';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 30,
        height: 40,
        child: CollectionCoverImage(
          url: url,
          width: 30,
          height: 40,
          bookCover: isBook,
          fit: isBook ? BoxFit.contain : BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildSinglePreview(ActivityEvent e) {
    final scheme = Theme.of(context).colorScheme;
    CollectionCategory? cat;
    if (e.itemCategory != null) {
      try {
        cat = CollectionCategory.fromDbValue(e.itemCategory!);
      } catch (_) {}
    }

    return Row(
      children: [
        if (e.itemImageUrl != null && e.itemImageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 28,
              height: 36,
              child: CollectionCoverImage(
                url: e.itemImageUrl!,
                width: 28,
                height: 36,
                bookCover: e.itemCategory == 'book',
                fit: e.itemCategory == 'book' ? BoxFit.contain : BoxFit.cover,
              ),
            ),
          )
        else if (cat != null)
          Container(
            width: 28,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(cat.icon, color: cat.color, size: 16),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            e.itemTitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.88),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _addButton(ActivityEvent e) {
    final loading = _addingItemId == e.itemId;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Ajouter à ma collection',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: loading ? null : () => _addFromActivity(e),
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          : Icon(Icons.add_circle_outline, color: scheme.primary, size: 20),
    );
  }

  void _showSingleDetail(ActivityEvent e) {
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
              _buildSinglePreview(e),
              if (_canAddFrom(e)) ...[
                const SizedBox(height: 12),
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
