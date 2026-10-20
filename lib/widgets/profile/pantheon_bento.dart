import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

/// Vitrine : podium or / argent / bronze, puis les places suivantes centrées.
class PantheonBento extends StatelessWidget {
  final List<CollectionItem> ranked;
  final bool editable;
  final int slotCount;
  final VoidCallback? onAutoFill;
  final ValueChanged<int>? onEditSlot;
  final ValueChanged<int>? onRemove;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final ValueChanged<CollectionItem>? onOpenItem;

  const PantheonBento({
    super.key,
    required this.ranked,
    this.editable = false,
    this.slotCount = 10,
    this.onAutoFill,
    this.onEditSlot,
    this.onRemove,
    this.onReorder,
    this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    if (!editable && ranked.isEmpty) return const SizedBox.shrink();
    final count = editable ? slotCount : ranked.length;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFC107).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '\u{1F3C6} Panthéon',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (editable && onAutoFill != null)
              TextButton(
                onPressed: onAutoFill,
                child: const Text('Remplir automatiquement mon Top'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final maxW = constraints.maxWidth;
            var side = ((maxW - gap * 2) / 3.15).clamp(72.0, 132.0);
            var center = (side * 1.14).clamp(84.0, 150.0);
            final total = side * 2 + center + gap * 2;
            if (total > maxW && maxW > 0) {
              final scale = maxW / total;
              side *= scale;
              center *= scale;
            }
            return Container(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFFD54F).withValues(alpha: 0.16),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _card(context, 1, width: side, height: side * 1.22),
                  const SizedBox(width: gap),
                  _card(context, 0, width: center, height: center * 1.48),
                  const SizedBox(width: gap),
                  _card(context, 2, width: side, height: side * 1.12),
                ],
              ),
            );
          },
        ),
        if (count > 3) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 3; i < count; i++)
                _card(context, i, width: 112, height: 168),
            ],
          ),
        ],
      ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    int index, {
    required double width,
    required double height,
  }) {
    if (!editable && index >= ranked.length) return const SizedBox.shrink();
    final item = index < ranked.length ? ranked[index] : null;
    final medal = _medalFor(index);
    final card = SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: medal?.edge ?? Colors.transparent,
            width: medal == null ? 0 : 2.4,
          ),
          boxShadow: medal == null
              ? null
              : [
                  BoxShadow(
                    color: medal.glow.withValues(alpha: 0.85),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: Padding(
          padding: EdgeInsets.all(medal == null ? 0 : 2),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (item != null && onOpenItem != null) {
                  onOpenItem!(item);
                } else if (editable && item == null && onEditSlot != null) {
                  onEditSlot!(index);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: item?.imageUrl != null
                        ? CollectionCoverImage(
                            key: ValueKey(item!.id),
                            url: item.imageUrl!,
                            boxedCover: true,
                            compact: true,
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            item == null
                                ? Icons.add_rounded
                                : Icons.category_outlined,
                            key: ValueKey('empty-$index'),
                            color: medal?.edge ??
                                Theme.of(context).colorScheme.primary,
                            size: 36,
                          ),
                  ),
                  if (medal != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: height * 0.46,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                medal.tint.withValues(alpha: 0),
                                medal.tint.withValues(alpha: 0.42),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (editable && item != null && onEditSlot != null)
                    Positioned(
                      right: 36,
                      top: 4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => onEditSlot!(index),
                        icon: const Icon(Icons.swap_horiz, size: 16),
                      ),
                    ),
                  if (editable && item != null && onRemove != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => onRemove!(index),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: medal == null
                            ? null
                            : LinearGradient(
                                colors: [medal.edge, medal.deep],
                              ),
                        color: medal == null ? Colors.black87 : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Text(
                        switch (index) {
                          0 => '\u{1F947} #1',
                          1 => '\u{1F948} #2',
                          2 => '\u{1F949} #3',
                          _ => '#${index + 1}',
                        },
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          shadows: [
                            Shadow(color: Colors.black45, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
                      child: Text(
                        item?.title ?? 'Choisir',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!editable || onReorder == null || (item == null && onEditSlot == null)) {
      return card;
    }
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onReorder!(details.data, index),
      builder: (context, candidate, _) {
        final highlighted = candidate.isNotEmpty;
        final body = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: card,
        );
        if (item == null) return body;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: card),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: card),
          child: body,
        );
      },
    );
  }
}

class _Medal {
  final Color edge;
  final Color deep;
  final Color glow;
  final Color tint;
  const _Medal(this.edge, this.deep, this.glow, this.tint);
}

_Medal? _medalFor(int index) {
  return switch (index) {
    0 => const _Medal(
        Color(0xFFFFD54F),
        Color(0xFFFF8F00),
        Color(0xFFFFC107),
        Color(0xFFFFE082),
      ),
    1 => const _Medal(
        Color(0xFFECEFF1),
        Color(0xFF78909C),
        Color(0xFFB0BEC5),
        Color(0xFFCFD8DC),
      ),
    2 => const _Medal(
        Color(0xFFE0A36A),
        Color(0xFF8D6E63),
        Color(0xFFBCAAA4),
        Color(0xFFD7CCC8),
      ),
    _ => null,
  };
}

Future<String?> showPantheonGamePicker(
  BuildContext context, {
  required int rank,
  required List<CollectionItem> games,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PantheonGamePicker(rank: rank, games: games),
  );
}

class _PantheonGamePicker extends StatefulWidget {
  final int rank;
  final List<CollectionItem> games;

  const _PantheonGamePicker({required this.rank, required this.games});

  @override
  State<_PantheonGamePicker> createState() => _PantheonGamePickerState();
}

class _PantheonGamePickerState extends State<_PantheonGamePicker> {
  final _query = TextEditingController();
  final _open = <CollectionCategory>{};

  @override
  void initState() {
    super.initState();
    final present = widget.games.map((g) => g.category).toSet();
    if (present.length <= 4) {
      _open.addAll(present);
    } else if (present.contains(CollectionCategory.boardgame)) {
      _open.add(CollectionCategory.boardgame);
    } else if (present.isNotEmpty) {
      _open.add(present.first);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final shown = widget.games
        .where((g) => q.isEmpty || g.title.toLowerCase().contains(q))
        .toList();
    final groups = <CollectionCategory, List<CollectionItem>>{};
    for (final item in shown) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final order = CollectionCategory.values
        .where(groups.containsKey)
        .toList();
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Place #${widget.rank}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Rechercher dans toutes tes collections',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('Aucun objet'))
                : ListView(
                    children: [
                      for (final category in order)
                        ExpansionTile(
                          key: ValueKey('${category.name}-$q'),
                          initiallyExpanded: _open.contains(category) || q.isNotEmpty,
                          leading: Text(
                            _categoryEmoji(category),
                            style: const TextStyle(fontSize: 20),
                          ),
                          title: Text(
                            '${category.label} (${groups[category]!.length})',
                          ),
                          children: [
                            for (final game in groups[category]!)
                              ListTile(
                                leading: SizedBox(
                                  width: 36,
                                  height: 48,
                                  child: game.imageUrl == null
                                      ? const Icon(Icons.image_outlined)
                                      : CollectionCoverImage(
                                          url: game.imageUrl!,
                                          compact: true,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                title: Text(
                                  game.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => Navigator.pop(context, game.id),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _categoryEmoji(CollectionCategory category) {
  return switch (category) {
    CollectionCategory.boardgame => '🎲',
    CollectionCategory.book => '📚',
    CollectionCategory.card => '🃏',
    CollectionCategory.media => '💿',
    CollectionCategory.lego => '🧱',
    CollectionCategory.videogame => '🎮',
    CollectionCategory.movie => '🎬',
    CollectionCategory.car => '🚗',
    CollectionCategory.stamp => '✉️',
    CollectionCategory.coin => '🪙',
    CollectionCategory.watch => '⌚',
    CollectionCategory.wildlife => '🐾',
    CollectionCategory.restaurant => '🍽️',
    CollectionCategory.tech => '💻',
    CollectionCategory.custom => '📦',
  };
}

class PantheonPlaceOption {
  final int index;
  final String? itemId;
  final String? title;
  final String? imageUrl;

  const PantheonPlaceOption({
    required this.index,
    this.itemId,
    this.title,
    this.imageUrl,
  });
}

Future<int?> showPantheonPlacePicker(
  BuildContext context, {
  required List<PantheonPlaceOption> places,
  int? alreadyAt,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Place dans le Panthéon'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (alreadyAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Déjà présent à la place #$alreadyAt',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: places.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final place = places[i];
                  final occupied = place.title != null && place.title!.isNotEmpty;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: 36,
                      height: 48,
                      child: !occupied || place.imageUrl == null
                          ? Icon(
                              occupied
                                  ? Icons.image_outlined
                                  : Icons.add_rounded,
                              color: Colors.grey,
                            )
                          : CollectionCoverImage(
                              url: place.imageUrl!,
                              compact: true,
                              fit: BoxFit.cover,
                            ),
                    ),
                    title: Text(
                      '#${place.index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      occupied ? place.title! : 'Vide',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(ctx, place.index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}
