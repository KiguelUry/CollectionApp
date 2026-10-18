import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/collection_item.dart';
import '../models/friend_choice.dart';
import '../services/friend_service.dart';
import '../services/notification_service.dart';
import '../services/profile_cache_service.dart';
import 'friend_identity.dart';
import '../utils/item_recommendation.dart';

class RecommendSelection {
  final List<FriendChoice> friends;
  final String? message;

  const RecommendSelection(this.friends, this.message);
}

/// Feuille « Recommander à un ami » : multi-sélection + message optionnel.
class RecommendFriendSheet extends StatefulWidget {
  final String itemTitle;
  final List<FriendChoice> friends;

  const RecommendFriendSheet({
    super.key,
    required this.itemTitle,
    required this.friends,
  });

  @override
  State<RecommendFriendSheet> createState() => _RecommendFriendSheetState();
}

class _RecommendFriendSheetState extends State<RecommendFriendSheet> {
  final _selected = <String>{};
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Recommander « ${widget.itemTitle} »',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in widget.friends)
                    ListTile(
                      leading: FriendAvatarButton(
                        profileId: f.profileId,
                        username: f.username,
                        avatarUrl: f.avatarUrl,
                        accentColor: f.accentColor,
                      ),
                      title: FriendNameButton(friend: f),
                      trailing: Checkbox(
                        key: ValueKey('recommend_friend_${f.profileId}'),
                        value: _selected.contains(f.profileId),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(f.profileId);
                          } else {
                            _selected.remove(f.profileId);
                          }
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _message,
                maxLength: 140,
                decoration: const InputDecoration(
                  labelText: 'Petit mot (optionnel)',
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: FilledButton.icon(
                key: const ValueKey('recommend_send'),
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        RecommendSelection(
                          widget.friends
                              .where((f) => _selected.contains(f.profileId))
                              .toList(),
                          _message.text,
                        ),
                      ),
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  _selected.length <= 1
                      ? 'Envoyer'
                      : 'Envoyer à ${_selected.length} amis',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton du détail d'objet : envoie une notification « recommandation ».
class RecommendToFriendButton extends StatelessWidget {
  final CollectionItem item;

  const RecommendToFriendButton({super.key, required this.item});

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final rows = await FriendService().fetchFriends();
    final friends = [
      for (final r in rows)
        FriendChoice.fromFriendRow(r),
    ];
    if (!context.mounted) return;
    if (friends.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Ajoute d\'abord des amis')),
      );
      return;
    }
    final selection = await showModalBottomSheet<RecommendSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          RecommendFriendSheet(itemTitle: item.title, friends: friends),
    );
    if (selection == null) return;

    final payload = buildRecommendationPayload(
      item,
      senderUsername:
          ProfileCacheService.instance.profile?.username ?? 'Un ami',
      message: selection.message,
    );
    var sent = 0;
    for (final f in selection.friends) {
      try {
        await NotificationService.instance.send(
          recipientId: f.profileId,
          type: AppNotificationType.itemRecommendation,
          payload: payload,
        );
        sent++;
      } catch (_) {}
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sent == 0
              ? 'Envoi impossible (notifications non configurées ?)'
              : 'Recommandation envoyée à $sent ami${sent > 1 ? 's' : ''}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('recommend_to_friend'),
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: const Text('Recommander'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: () => _open(context),
    );
  }
}
