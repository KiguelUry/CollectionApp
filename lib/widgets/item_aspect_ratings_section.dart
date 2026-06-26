import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import 'star_rating_bar.dart';

class AspectRating {
  final String key;
  final String label;

  const AspectRating({required this.key, required this.label});
}

List<AspectRating> aspectRatingsForCategory(CollectionCategory category) {
  return switch (category) {
    CollectionCategory.boardgame => const [
        AspectRating(key: 'gameplay', label: 'Gameplay'),
        AspectRating(key: 'strategy', label: 'Stratégie'),
        AspectRating(key: 'art', label: 'DA / composants'),
        AspectRating(key: 'fun', label: 'Ambiance'),
      ],
    CollectionCategory.book => const [
        AspectRating(key: 'story', label: 'Histoire'),
        AspectRating(key: 'writing', label: 'Écriture'),
        AspectRating(key: 'pacing', label: 'Rythme'),
        AspectRating(key: 'overall_feel', label: 'Impression générale'),
      ],
    CollectionCategory.media => const [
        AspectRating(key: 'sound', label: 'Son'),
        AspectRating(key: 'production', label: 'Production'),
        AspectRating(key: 'artwork', label: 'Pochette / visuel'),
        AspectRating(key: 'replay', label: 'Réécoutabilité'),
      ],
    CollectionCategory.movie => const [
        AspectRating(key: 'story', label: 'Scénario'),
        AspectRating(key: 'acting', label: 'Jeu d\'acteurs'),
        AspectRating(key: 'visuals', label: 'Image'),
        AspectRating(key: 'soundtrack', label: 'Bande-son'),
      ],
    CollectionCategory.videogame => const [
        AspectRating(key: 'gameplay', label: 'Gameplay'),
        AspectRating(key: 'story', label: 'Histoire'),
        AspectRating(key: 'graphics', label: 'Graphismes'),
        AspectRating(key: 'soundtrack', label: 'Bande-son'),
      ],
    _ => const [
        AspectRating(key: 'quality', label: 'Qualité'),
        AspectRating(key: 'value', label: 'Rapport qualité/prix'),
        AspectRating(key: 'design', label: 'Design'),
        AspectRating(key: 'other', label: 'Autre'),
      ],
  };
}

Map<String, double> parseAspectRatings(Map<String, dynamic>? metadata) {
  final raw = metadata?['aspect_ratings'];
  if (raw is! Map) return {};
  final out = <String, double>{};
  for (final e in raw.entries) {
    final v = e.value;
    if (v is num) out[e.key.toString()] = v.toDouble();
  }
  return out;
}

/// Notes détaillées par critère, stockées dans metadata.aspect_ratings.
class ItemAspectRatingsSection extends StatefulWidget {
  final CollectionCategory category;
  final Map<String, dynamic>? metadata;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;

  const ItemAspectRatingsSection({
    super.key,
    required this.category,
    required this.metadata,
    required this.readOnly,
    required this.onMetadataChanged,
  });

  @override
  State<ItemAspectRatingsSection> createState() =>
      _ItemAspectRatingsSectionState();
}

class _ItemAspectRatingsSectionState extends State<ItemAspectRatingsSection> {
  late Map<String, double> _ratings;

  @override
  void initState() {
    super.initState();
    _ratings = parseAspectRatings(widget.metadata);
  }

  @override
  void didUpdateWidget(ItemAspectRatingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata != widget.metadata) {
      _ratings = parseAspectRatings(widget.metadata);
    }
  }

  void _setRating(String key, double value) {
    final next = Map<String, double>.from(_ratings);
    if (value <= 0) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    setState(() => _ratings = next);
    final meta = Map<String, dynamic>.from(widget.metadata ?? {});
    if (next.isEmpty) {
      meta.remove('aspect_ratings');
    } else {
      meta['aspect_ratings'] = next;
    }
    widget.onMetadataChanged(meta);
  }

  @override
  Widget build(BuildContext context) {
    final aspects = aspectRatingsForCategory(widget.category);
    final hasAny = _ratings.values.any((v) => v > 0);

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'Notes par critère',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        hasAny
            ? '${_ratings.values.where((v) => v > 0).length} critère(s) noté(s)'
            : 'Gameplay, stratégie, DA…',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      children: [
        for (final aspect in aspects) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    aspect.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: StarRatingBar(
                    rating: _ratings[aspect.key] ?? 0,
                    onChanged: widget.readOnly
                        ? (_) {}
                        : (v) => _setRating(aspect.key, v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
