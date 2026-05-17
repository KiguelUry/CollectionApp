import 'package:flutter/material.dart';

class GroupIconOption {
  final String key;
  final IconData icon;
  final String label;

  const GroupIconOption({
    required this.key,
    required this.icon,
    required this.label,
  });
}

const List<GroupIconOption> groupIconOptions = [
  GroupIconOption(key: 'groups', icon: Icons.groups, label: 'Groupe'),
  GroupIconOption(
    key: 'family_restroom',
    icon: Icons.family_restroom,
    label: 'Famille',
  ),
  GroupIconOption(key: 'home', icon: Icons.home, label: 'Maison'),
  GroupIconOption(key: 'favorite', icon: Icons.favorite, label: 'Cœur'),
  GroupIconOption(key: 'casino', icon: Icons.casino, label: 'Jeux'),
  GroupIconOption(
    key: 'sports_esports',
    icon: Icons.sports_esports,
    label: 'Jeux vidéo',
  ),
  GroupIconOption(key: 'pets', icon: Icons.pets, label: 'Animaux'),
  GroupIconOption(
    key: 'celebration',
    icon: Icons.celebration,
    label: 'Fête',
  ),
  GroupIconOption(key: 'school', icon: Icons.school, label: 'École'),
  GroupIconOption(
    key: 'travel_explore',
    icon: Icons.travel_explore,
    label: 'Voyage',
  ),
  GroupIconOption(
    key: 'restaurant',
    icon: Icons.restaurant,
    label: 'Cuisine',
  ),
  GroupIconOption(
    key: 'music_note',
    icon: Icons.music_note,
    label: 'Musique',
  ),
];

IconData groupIconFromKey(String? key) {
  if (key == null || key.isEmpty) return Icons.groups;
  for (final opt in groupIconOptions) {
    if (opt.key == key) return opt.icon;
  }
  return Icons.groups;
}
