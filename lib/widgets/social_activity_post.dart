import 'package:flutter/material.dart';

import '../models/activity_event.dart';
import '../models/collection_category.dart';
import '../utils/activity_feed_grouper.dart';
import 'collection_cover_image.dart';

/// Densité mosaïque par slide du carrousel d'activité.
enum FeedMosaicDensity {
  auto,
  one,
  two,
  four,
  eight,
  sixteen;

  int get tilesPerSlide => switch (this) {
        FeedMosaicDensity.auto => 0,
        FeedMosaicDensity.one => 1,
        FeedMosaicDensity.two => 2,
        FeedMosaicDensity.four => 4,
        FeedMosaicDensity.eight => 8,
        FeedMosaicDensity.sixteen => 16,
      };

  String get label => switch (this) {
        FeedMosaicDensity.auto => 'Auto',
        FeedMosaicDensity.one => '1 (Polaroid)',
        FeedMosaicDensity.two => '2',
        FeedMosaicDensity.four => '4 (2×2)',
        FeedMosaicDensity.eight => '8 (4×2)',
        FeedMosaicDensity.sixteen => '16 (4×4)',
      };
}

enum FeedActivityKindFilter { all, collection, wishlist, ratings }

/// Choisit la densité effective pour un lot d'événements.
int resolveMosaicTiles(int count, FeedMosaicDensity density) {
  if (density != FeedMosaicDensity.auto) {
    final forced = density.tilesPerSlide;
    // Ne jamais inventer de cases vides : plafonner au nombre d'événements.
    if (forced <= 0) return count.clamp(1, 16);
    return forced.clamp(1, count.clamp(1, 16));
  }
  if (count <= 1) return 1;
  if (count <= 2) return 2;
  if (count <= 4) return 4;
  if (count <= 6) return 6;
  if (count <= 9) return 9;
  return 12;
}

bool feedEventMatchesKind(ActivityEvent e, FeedActivityKindFilter kind) {
  return switch (kind) {
    FeedActivityKindFilter.all => true,
    FeedActivityKindFilter.collection => e.eventType == 'item_added',
    FeedActivityKindFilter.wishlist => e.eventType == 'wishlist_added',
    FeedActivityKindFilter.ratings =>
      e.eventType == 'item_rated' || e.eventType == 'trophies_updated',
  };
}

String feedVerbFor(ActivityFeedGroup group) {
  final e = group.head;
  return switch (e.eventType) {
    'item_rated' => 'a noté',
    'wishlist_added' => group.isBurst
        ? 'a mis en wishlist'
        : 'wishlist',
    'trophies_updated' => 'trophées',
    'item_added' => group.isBurst ? 'a ajouté' : 'a ajouté',
    _ => 'activité',
  };
}

String? categoryBadgeLabel(String? dbValue) {
  if (dbValue == null || dbValue.isEmpty) return null;
  try {
    return CollectionCategory.fromDbValue(dbValue).label;
  } catch (_) {
    return null;
  }
}

/// Carte Polaroid / mosaïque pour une publication d'activité.
class SocialActivityPost extends StatefulWidget {
  final ActivityFeedGroup group;
  final String actorName;
  final String? actorAvatarUrl;
  final String? actorAccentColor;
  final Widget actorAvatar;
  final String timeAgo;
  final FeedMosaicDensity density;
  final Map<String, String> reactions;
  final Map<String, Map<String, int>> reactionCounts;
  final List<String> emojis;
  final void Function(String eventId, String emoji) onReact;
  final ValueChanged<ActivityEvent> onOpenItem;
  final ValueChanged<ActivityEvent>? onQuickWishlist;
  final String? addingItemId;

  const SocialActivityPost({
    super.key,
    required this.group,
    required this.actorName,
    this.actorAvatarUrl,
    this.actorAccentColor,
    required this.actorAvatar,
    required this.timeAgo,
    required this.density,
    required this.reactions,
    required this.reactionCounts,
    required this.emojis,
    required this.onReact,
    required this.onOpenItem,
    this.onQuickWishlist,
    this.addingItemId,
  });

  @override
  State<SocialActivityPost> createState() => _SocialActivityPostState();
}

class _SocialActivityPostState extends State<SocialActivityPost> {
  late final PageController _page;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final e = group.head;
    final tiles = resolveMosaicTiles(group.count, widget.density);
    final slides = _chunk(group.events, tiles);
    final cat = categoryBadgeLabel(e.itemCategory);
    final isWishlist = e.eventType == 'wishlist_added';
    final verb = feedVerbFor(group);
    final summary = group.isBurst
        ? '$verb ${group.count} objet${group.count > 1 ? 's' : ''}'
        : '$verb ${e.itemTitle ?? 'un objet'}'
            '${e.eventType == 'item_rated' && e.rating != null ? ' ${e.rating}★' : ''}';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                widget.actorAvatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: widget.actorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            TextSpan(
                              text: '  $summary',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (cat != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // PC : ratio story 4:5 max ; mosaïque un peu plus large.
              final wide = constraints.maxWidth >= 520;
              final ratio = tiles == 1
                  ? (wide ? 1.15 : 0.95)
                  : (wide ? 1.55 : 1.25);
              return AspectRatio(
                aspectRatio: ratio,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _page,
                      itemCount: slides.length,
                      onPageChanged: (i) => setState(() => _pageIndex = i),
                      itemBuilder: (context, i) => _MosaicSlide(
                        events: slides[i],
                        tilesPerSlide: tiles,
                        isWishlist: isWishlist,
                        onOpen: widget.onOpenItem,
                        onQuickWishlist: widget.onQuickWishlist,
                        addingItemId: widget.addingItemId,
                      ),
                    ),
                    // Flèches aussi sur slide unique multi-items? Non — multi-pages only.
                    // Sur PC le scroll horizontal souris marche ; flèches restent cliquables.
                    if (slides.length > 1) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _navArrow(
                          Icons.chevron_left_rounded,
                          () => _page.previousPage(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOut,
                          ),
                          enabled: _pageIndex > 0,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _navArrow(
                          Icons.chevron_right_rounded,
                          () => _page.nextPage(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOut,
                          ),
                          enabled: _pageIndex < slides.length - 1,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 10,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < slides.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: i == _pageIndex ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _pageIndex
                                      ? Colors.white
                                      : Colors.white38,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_pageIndex + 1}/${slides.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                for (final emoji in widget.emojis)
                  InkWell(
                    onTap: () => widget.onReact(e.id, emoji),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Opacity(
                        opacity: widget.reactions[e.id] == emoji ? 1 : 0.55,
                        child: Text(
                          (widget.reactionCounts[e.id]?[emoji] ?? 0) > 0
                              ? '$emoji ${widget.reactionCounts[e.id]![emoji]}'
                              : emoji,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  widget.timeAgo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap, {required bool enabled}) {
    return Opacity(
      opacity: enabled ? 1 : 0.25,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  List<List<ActivityEvent>> _chunk(List<ActivityEvent> events, int size) {
    if (events.isEmpty) return const [];
    final n = size.clamp(1, 64);
    final out = <List<ActivityEvent>>[];
    for (var i = 0; i < events.length; i += n) {
      out.add(events.sublist(i, (i + n).clamp(0, events.length)));
    }
    return out;
  }
}

class _MosaicSlide extends StatelessWidget {
  final List<ActivityEvent> events;
  final int tilesPerSlide;
  final bool isWishlist;
  final ValueChanged<ActivityEvent> onOpen;
  final ValueChanged<ActivityEvent>? onQuickWishlist;
  final String? addingItemId;

  const _MosaicSlide({
    required this.events,
    required this.tilesPerSlide,
    required this.isWishlist,
    required this.onOpen,
    this.onQuickWishlist,
    this.addingItemId,
  });

  @override
  Widget build(BuildContext context) {
    final n = events.length.clamp(1, tilesPerSlide);
    if (n <= 1) {
      return _PolaroidTile(
        event: events.first,
        large: true,
        isWishlist: isWishlist,
        onOpen: onOpen,
        onQuickWishlist: onQuickWishlist,
        adding: addingItemId == events.first.itemId,
      );
    }
    // Grille dimensionnée sur le nombre réel d'items (pas de cases vides).
    final cols = n <= 2
        ? 2
        : n <= 4
            ? 2
            : n <= 6
                ? 3
                : 3;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.78,
        ),
        itemCount: n,
        itemBuilder: (context, i) => _PolaroidTile(
          event: events[i],
          large: false,
          isWishlist: isWishlist,
          onOpen: onOpen,
          onQuickWishlist: onQuickWishlist,
          adding: addingItemId == events[i].itemId,
        ),
      ),
    );
  }
}

class _PolaroidTile extends StatelessWidget {
  final ActivityEvent event;
  final bool large;
  final bool isWishlist;
  final ValueChanged<ActivityEvent> onOpen;
  final ValueChanged<ActivityEvent>? onQuickWishlist;
  final bool adding;

  const _PolaroidTile({
    required this.event,
    required this.large,
    required this.isWishlist,
    required this.onOpen,
    this.onQuickWishlist,
    this.adding = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = event.itemImageUrl;
    final book = event.itemCategory == 'book';
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(large ? 0 : 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(event),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              CollectionCoverImage(
                url: url,
                // Contenir : plus de couvertures tronquées / cases « coupées ».
                fit: BoxFit.contain,
                bookCover: book,
                boxedCover: !book,
              )
            else
              ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_outlined,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  size: large ? 48 : 28,
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  large ? 12 : 6,
                  large ? 28 : 16,
                  large ? 12 : 6,
                  large ? 10 : 6,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.itemTitle ?? 'Objet',
                      maxLines: large ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: large ? 19 : 13,
                        letterSpacing: large ? -0.3 : 0,
                        height: 1.12,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 10,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    if (large) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (isWishlist)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.pinkAccent.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Wishlist',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (event.rating != null) ...[
                            if (isWishlist) const SizedBox(width: 6),
                            Text(
                              '★ ${event.rating}',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (onQuickWishlist != null &&
                              event.itemId != null &&
                              !isWishlist)
                            IconButton(
                              tooltip: '+ Wishlist',
                              visualDensity: VisualDensity.compact,
                              color: Colors.white,
                              onPressed: adding
                                  ? null
                                  : () => onQuickWishlist!(event),
                              icon: adding
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.favorite_border, size: 18),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
