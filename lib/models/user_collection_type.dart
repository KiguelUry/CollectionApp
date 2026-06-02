import 'package:flutter/material.dart';

/// Collection personnalisée créée par l'utilisateur.
class UserCollectionType {
  final String id;
  final String name;
  final String iconKey;
  final Color color;

  const UserCollectionType({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
  });

  factory UserCollectionType.fromJson(Map<String, dynamic> json) {
    return UserCollectionType(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Collection',
      iconKey: json['icon_key']?.toString() ?? 'category',
      color: _colorFromHex(json['color_hex']?.toString()),
    );
  }

  Map<String, dynamic> toInsertJson(String ownerId) => {
        'owner_id': ownerId,
        'name': name.trim(),
        'icon_key': iconKey,
        'color_hex': _colorToHex(color),
      };

  static Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueGrey;
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    if (v == null) return Colors.blueGrey;
    return Color(v);
  }

  static String _colorToHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  IconData get icon => iconFromKey(iconKey);

  static IconData iconFromKey(String key) => switch (key) {
        'toys' => Icons.toys_outlined,
        'sports' => Icons.sports_soccer,
        'photo' => Icons.photo_camera_outlined,
        'art' => Icons.palette_outlined,
        'computer' => Icons.computer_outlined,
        'home' => Icons.home_outlined,
        'pets' => Icons.pets_outlined,
        'wine' => Icons.wine_bar_outlined,
        'star' => Icons.star_outline,
        _ => Icons.category_outlined,
      };

  static const iconChoices = [
    ('category', 'Général'),
    ('toys', 'Objets'),
    ('art', 'Art'),
    ('photo', 'Photo'),
    ('sports', 'Sport'),
    ('computer', 'Tech'),
    ('home', 'Maison'),
    ('pets', 'Animaux'),
    ('wine', 'Vin & spiritueux'),
    ('star', 'Favoris'),
  ];

  static const colorChoices = [
    Colors.blueGrey,
    Colors.indigo,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.deepPurple,
    Colors.pink,
    Colors.brown,
    Colors.cyan,
  ];
}
