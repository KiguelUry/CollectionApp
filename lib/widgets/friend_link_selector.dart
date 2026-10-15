import 'package:flutter/material.dart';

import '../models/friend_choice.dart';

/// Case « Cette personne est dans ma liste d'amis » + choix de l'ami.
class FriendLinkSelector extends StatelessWidget {
  final List<FriendChoice> friends;
  final bool linked;
  final FriendChoice? selected;
  final ValueChanged<bool> onLinkedChanged;
  final ValueChanged<FriendChoice?> onSelected;

  const FriendLinkSelector({
    super.key,
    required this.friends,
    required this.linked,
    required this.onLinkedChanged,
    required this.onSelected,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          key: const ValueKey('is_friend_checkbox'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: linked,
          title: const Text('Cette personne est dans ma liste d\'amis'),
          subtitle: const Text(
            'Elle pourra ajouter vos parties à son historique',
          ),
          onChanged: (v) => onLinkedChanged(v ?? false),
        ),
        if (linked)
          DropdownButtonFormField<String>(
            key: const ValueKey('friend_selector'),
            initialValue: selected?.profileId,
            decoration: const InputDecoration(
              labelText: 'Ami',
              prefixIcon: Icon(Icons.people_alt_outlined),
              isDense: true,
            ),
            items: [
              for (final f in friends)
                DropdownMenuItem(value: f.profileId, child: Text(f.username)),
            ],
            onChanged: (id) =>
                onSelected(friends.where((f) => f.profileId == id).firstOrNull),
          ),
      ],
    );
  }
}
