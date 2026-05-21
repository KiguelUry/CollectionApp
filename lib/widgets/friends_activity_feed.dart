import 'package:flutter/material.dart';

import '../models/activity_event.dart';
import '../services/activity_service.dart';
import 'profile_avatar.dart';

/// Fil d'activité des amis (ajouts, notes, trophées).
class FriendsActivityFeed extends StatefulWidget {
  const FriendsActivityFeed({super.key});

  @override
  State<FriendsActivityFeed> createState() => _FriendsActivityFeedState();
}

class _FriendsActivityFeedState extends State<FriendsActivityFeed> {
  final _service = ActivityService();
  List<ActivityEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      _events = await _service.fetchFriendsFeed();
    } catch (e) {
      _events = [];
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'wishlist_added' => Icons.favorite_border,
      'item_rated' => Icons.star,
      'trophies_updated' => Icons.emoji_events,
      _ => Icons.add_circle_outline,
    };
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
    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Icon(Icons.dynamic_feed_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Pas encore d\'activité',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Quand tes amis ajoutent des objets ou notent leur collection, '
                'ça apparaît ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final e = _events[index];
          return Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: ProfileAvatar(
                avatarUrl: e.actorAvatarUrl,
                accentColorHex: e.actorAccentColor,
                fallbackInitial: e.actorUsername,
                radius: 22,
              ),
              title: Text(
                e.description,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                _timeAgo(e.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              trailing: Icon(_iconFor(e.eventType), color: Colors.amber.shade800),
            ),
          );
        },
      ),
    );
  }
}
