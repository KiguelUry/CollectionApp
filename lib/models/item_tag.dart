import 'package:flutter/material.dart';

class ItemTag {
  final String id;
  final String label;
  final String colorHex;

  const ItemTag({
    required this.id,
    required this.label,
    this.colorHex = '#9E9E9E',
  });

  factory ItemTag.fromJson(Map<String, dynamic> json) {
    return ItemTag(
      id: json['id'] as String,
      label: json['label'] as String,
      colorHex: (json['color'] as String?) ?? '#9E9E9E',
    );
  }

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    if (hex.length != 6) return Colors.grey;
    return Color(int.parse('FF$hex', radix: 16));
  }

  static List<ItemTag> parseListFromItemJson(Map<String, dynamic> json) {
    final links = json['collection_item_tags'];
    if (links is! List) return const [];

    final tags = <ItemTag>[];
    for (final link in links) {
      if (link is! Map) continue;
      final tagJson = link['item_tags'];
      if (tagJson is Map) {
        tags.add(ItemTag.fromJson(Map<String, dynamic>.from(tagJson)));
      }
    }
    tags.sort((a, b) => a.label.compareTo(b.label));
    return tags;
  }
}

const tagColorPresets = [
  '#9E9E9E',
  '#673AB7',
  '#2196F3',
  '#4CAF50',
  '#FF9800',
  '#E91E63',
  '#009688',
  '#795548',
];
