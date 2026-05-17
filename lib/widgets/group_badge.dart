import 'package:flutter/material.dart';
import '../models/group_icon.dart';
import 'profile_avatar.dart';

/// Badge visuel d'un groupe (photo, icône + couleur).
class GroupBadge extends StatelessWidget {
  final String? avatarUrl;
  final String? accentColorHex;
  final String iconKey;
  final String fallbackInitial;
  final double radius;

  const GroupBadge({
    super.key,
    this.avatarUrl,
    this.accentColorHex,
    this.iconKey = 'groups',
    required this.fallbackInitial,
    this.radius = 24,
  });

  factory GroupBadge.fromGroup({
    required String name,
    String? avatarUrl,
    String? accentColor,
    String iconKey = 'groups',
    double radius = 24,
  }) {
    return GroupBadge(
      avatarUrl: avatarUrl,
      accentColorHex: accentColor,
      iconKey: iconKey,
      fallbackInitial: name,
      radius: radius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ProfileAvatar.colorFromHex(accentColorHex);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image.network(
            avatarUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _iconBadge(accent),
          ),
        ),
      );
    }

    return _iconBadge(accent);
  }

  Widget _iconBadge(Color accent) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent,
      child: Icon(
        groupIconFromKey(iconKey),
        color: Colors.white,
        size: radius,
      ),
    );
  }
}
