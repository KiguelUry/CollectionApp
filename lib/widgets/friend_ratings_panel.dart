import 'package:flutter/material.dart';

import '../models/collection_item.dart';
import '../services/friend_ratings_service.dart';
import '../widgets/friend_rating_detail_sheet.dart';
import '../widgets/profile_avatar.dart';

/// Avis et notes des amis sur le même objet (style Letterboxd).
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

  static const _emptyMessage = 'Aucun avis pour le moment.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await _service.fetchFriendRatingsForItem(widget.item);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
      });
    }
  }

  void _openEntry(FriendRatingEntry entry) {
    FriendRatingDetailSheet.show(
      context,
      profileId: entry.profileId,
      username: entry.username,
      avatarUrl: entry.avatarUrl,
      itemTitle: entry.itemTitle,
      rating: entry.rating,
      review: entry.review,
    );
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
        const SizedBox(height: 10),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_entries.isEmpty)
          Text(
            _emptyMessage,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _entries.map(_buildFriendChip).toList(),
          ),
      ],
    );
  }

  Widget _buildFriendChip(FriendRatingEntry entry) {
    final hasReview = entry.review != null && entry.review!.trim().isNotEmpty;

    return InkWell(
      onTap: () => _openEntry(entry),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileAvatar(
                  avatarUrl: entry.avatarUrl,
                  fallbackInitial: entry.username.isNotEmpty
                      ? entry.username[0].toUpperCase()
                      : '?',
                  radius: 26,
                ),
                if (hasReview)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final filled = entry.rating >= i + 1;
                return Icon(
                  filled ? Icons.star : Icons.star_border,
                  size: 13,
                  color: Colors.amber.shade700,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
