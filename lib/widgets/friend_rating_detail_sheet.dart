import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/friend_collection_screen.dart';
import '../services/friend_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/star_rating_bar.dart';

/// Profil ami + avis sur un objet (style Letterboxd).
class FriendRatingDetailSheet extends StatelessWidget {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final String itemTitle;
  final int rating;
  final String? review;

  const FriendRatingDetailSheet({
    super.key,
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    required this.itemTitle,
    required this.rating,
    this.review,
  });

  static Future<void> show(
    BuildContext context, {
    required String profileId,
    required String username,
    String? avatarUrl,
    String? accentColor,
    required String itemTitle,
    required int rating,
    String? review,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FriendRatingDetailSheet(
        profileId: profileId,
        username: username,
        avatarUrl: avatarUrl,
        accentColor: accentColor,
        itemTitle: itemTitle,
        rating: rating,
        review: review,
      ),
    );
  }

  Future<void> _openFullProfile(BuildContext context) async {
    Navigator.pop(context);
    final friendService = FriendService();
    final share = await friendService.canViewFriendCollection(profileId);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendCollectionScreen(
          profileId: profileId,
          username: username,
          avatarUrl: avatarUrl,
          accentColor: accentColor,
          shareCollections: share,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(
      accentColor ?? profileAccentPresets.first,
    );
    final hasReview = review != null && review!.trim().isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  avatarUrl: avatarUrl,
                  accentColorHex: accentColor,
                  fallbackInitial:
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                  radius: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      StarRatingBar(rating: rating.toDouble(), onChanged: (_) {}),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Avis de $username sur « $itemTitle »',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
            ),
            const SizedBox(height: 10),
            if (hasReview)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  review!.trim(),
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              )
            else
              Text(
                'Pas de texte — seulement une note.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openFullProfile(context),
              icon: const Icon(Icons.person_outline),
              label: const Text('Voir le profil'),
            ),
          ],
        ),
      ),
    );
  }
}
