import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/videogame_metadata.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/collection_cover_image.dart';
import 'item_detail_screen.dart';

/// Classement personnel des jeux vidéo (notes, avis, % finition).
class VideogameRankingScreen extends StatefulWidget {
  const VideogameRankingScreen({super.key});

  @override
  State<VideogameRankingScreen> createState() => _VideogameRankingScreenState();
}

class _VideogameRankingScreenState extends State<VideogameRankingScreen> {
  static final _accent = Colors.green.shade700;

  List<CollectionItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final rows = await Supabase.instance.client
        .from('collection_items')
        .select()
        .or('added_by.eq.$userId,location_user_id.eq.$userId')
        .eq('category', CollectionCategory.videogame.dbValue)
        .eq('is_wishlist', false);
    final all = (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where((i) => !i.isSold && (i.rating ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        final ra = a.rating ?? 0;
        final rb = b.rating ?? 0;
        final cmp = rb.compareTo(ra);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      });
    if (mounted) {
      setState(() {
        _items = all;
        _loading = false;
      });
    }
  }

  void _openItem(CollectionItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(item: item),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHubHeader(
            title: 'Mon classement',
            accentColor: _accent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Tes jeux notés, du meilleur au moins bon',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.emoji_events_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Aucun jeu noté',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Ajoute une note sur tes jeux pour les voir ici.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final rank = index + 1;
                            return _RankingCard(
                              rank: rank,
                              item: item,
                              accent: _accent,
                              scheme: scheme,
                              onTap: () => _openItem(item),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  final int rank;
  final CollectionItem item;
  final Color accent;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _RankingCard({
    required this.rank,
    required this.item,
    required this.accent,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rating = item.rating ?? 0;
    final year = item.metadata?['year']?.toString();
    final platforms = videogamePlatformsLabel(item.metadata);
    final completion = videogameCompletionPercent(item.metadata);
    final status = videogamePlayStatus(item.metadata);
    final review = item.review?.trim();

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: accent.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? CollectionCoverImage(
                                url: item.imageUrl!,
                                fit: BoxFit.cover,
                              )
                            : ColoredBox(
                                color: accent.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.sports_esports,
                                  color: accent,
                                  size: 36,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(rating == rating.roundToDouble() ? 0 : 1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        '$rank.',
                        item.title,
                        if (year != null && year.isNotEmpty) '($year)',
                      ].join(' '),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (platforms.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        platforms,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (completion != null && completion > 0)
                          _InfoChip(
                            icon: Icons.flag_rounded,
                            label: '$completion %',
                            color: accent,
                          ),
                        _InfoChip(
                          icon: Icons.play_circle_outline,
                          label: status.label,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                    if (review != null && review.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Mon avis — ',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: review.length > 160
                                  ? '${review.substring(0, 157)}…'
                                  : review,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
