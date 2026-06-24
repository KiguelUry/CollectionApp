import 'package:flutter/material.dart';

import '../models/collection_item.dart';
import '../services/friend_ratings_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/star_rating_bar.dart';

/// Avis et notes des amis sur le même objet.
class FriendRatingsPanel extends StatefulWidget {
  final CollectionItem item;

  const FriendRatingsPanel({super.key, required this.item});

  @override
  State<FriendRatingsPanel> createState() => _FriendRatingsPanelState();
}

class _FriendRatingsPanelState extends State<FriendRatingsPanel> {
  final _service = FriendRatingsService();
  List<FriendRatingEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _service.fetchFriendRatingsForItem(widget.item);
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Notes de mes amis',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_entries.isEmpty)
          Text(
            'Aucun ami n\'a encore noté cet objet.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          )
        else
          ..._entries.map(
            (e) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: ProfileAvatar(
                  avatarUrl: e.avatarUrl,
                  fallbackInitial: e.username.isNotEmpty
                      ? e.username[0].toUpperCase()
                      : '?',
                  radius: 20,
                ),
                title: Text(e.username),
                subtitle: e.review != null && e.review!.trim().isNotEmpty
                    ? Text(e.review!, maxLines: 3)
                    : null,
                trailing: StarRatingBar(
                  rating: e.rating.toDouble(),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
      ],
    );
  }
}
