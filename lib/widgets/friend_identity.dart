import 'package:flutter/material.dart';

import '../models/friend_choice.dart';
import '../screens/friend_collection_screen.dart';
import 'profile_avatar.dart';

/// Ouvre la collection / le profil d'un ami de l'app.
void openFriendProfile(
  BuildContext context, {
  required String profileId,
  required String username,
  String? avatarUrl,
  String? accentColor,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FriendCollectionScreen(
        profileId: profileId,
        username: username,
        avatarUrl: avatarUrl,
        accentColor: accentColor,
        shareCollections: true,
      ),
    ),
  );
}

/// Tête cliquable : photo, ou initiales colorées si pas d'avatar.
class FriendAvatarButton extends StatelessWidget {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  final double radius;

  const FriendAvatarButton({
    super.key,
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Profil de $username',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => openFriendProfile(
          context,
          profileId: profileId,
          username: username,
          avatarUrl: avatarUrl,
          accentColor: accentColor,
        ),
        child: ProfileAvatar(
          avatarUrl: avatarUrl,
          accentColorHex: accentColor,
          fallbackInitial: username,
          radius: radius,
        ),
      ),
    );
  }
}

/// Nom cliquable qui ouvre le même profil.
class FriendNameButton extends StatelessWidget {
  final FriendChoice friend;
  final TextStyle? style;

  const FriendNameButton({super.key, required this.friend, this.style});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openFriendProfile(
        context,
        profileId: friend.profileId,
        username: friend.username,
        avatarUrl: friend.avatarUrl,
        accentColor: friend.accentColor,
      ),
      child: Text(friend.username, style: style),
    );
  }
}
