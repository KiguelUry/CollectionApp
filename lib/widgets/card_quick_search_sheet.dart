import 'package:flutter/material.dart';

import '../models/card_subcategory.dart';
import '../services/card_catalog_service.dart';
import 'bgg_network_image.dart';
import 'ui/empty_state.dart';

/// Recherche rapide carte : univers + résultats (bottom sheet).
Future<Map<String, String>?> showCardQuickSearchSheet(
  BuildContext context, {
  CardSubcategory initialSub = CardSubcategory.pokemon,
  VoidCallback? onManualEntry,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _CardQuickSearchSheet(
      initialSub: initialSub,
      onManualEntry: onManualEntry,
    ),
  );
}

class _CardQuickSearchSheet extends StatefulWidget {
  final CardSubcategory initialSub;
  final VoidCallback? onManualEntry;

  const _CardQuickSearchSheet({
    required this.initialSub,
    this.onManualEntry,
  });

  @override
  State<_CardQuickSearchSheet> createState() => _CardQuickSearchSheetState();
}

class _CardQuickSearchSheetState extends State<_CardQuickSearchSheet> {
  late CardSubcategory _sub = widget.initialSub;
  final _controller = TextEditingController();
  List<Map<String, String>> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 2) return;

    setState(() {
      _loading = true;
      _searched = true;
    });

    final res = await CardCatalogService.search(q, subcategory: _sub);

    if (!mounted) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final catalog = CardCatalogService.catalogLabel(_sub);

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Trouver une carte',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final s in CardSubcategory.values.where(
                  (c) => c.supportsCatalogSearch,
                ))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.label, style: const TextStyle(fontSize: 12)),
                      selected: _sub == s,
                      onSelected: (_) {
                        setState(() => _sub = s);
                        if (_controller.text.trim().length >= 2) _search();
                      },
                      avatar: Icon(s.icon, size: 16, color: s.color),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: _sub == CardSubcategory.pokemon
                    ? 'Dracaufeu, Pikachu…'
                    : 'Nom de la carte…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text(
              catalog,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildBody(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  if (widget.onManualEntry != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onManualEntry!();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Saisie manuelle'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return EmptyState(
        key: const ValueKey('hint'),
        icon: Icons.style_outlined,
        title: 'Tape au moins 2 lettres',
        message: 'Choisis l\'univers puis lance la recherche.',
        iconColor: _sub.color,
      );
    }
    if (_loading) {
      return const Center(
        key: ValueKey('load'),
        child: CircularProgressIndicator(),
      );
    }
    if (_results.isEmpty) {
      return EmptyState(
        key: const ValueKey('empty'),
        icon: Icons.sentiment_dissatisfied_outlined,
        title: 'Aucun résultat',
        message: 'Essaie un autre nom ou passe en saisie manuelle.',
        iconColor: _sub.color,
      );
    }
    return ListView.separated(
      key: const ValueKey('list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final c = _results[i];
        final img = c['image_url'];
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.pop(context, c),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: img != null && img.isNotEmpty
                        ? SizedBox(
                            width: 48,
                            height: 66,
                            child: BggNetworkImage(url: img),
                          )
                        : Container(
                            width: 48,
                            height: 66,
                            color: _sub.color.withValues(alpha: 0.12),
                            child: Icon(Icons.style, color: _sub.color),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['title'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if ((c['set_name'] ?? '').isNotEmpty) c['set_name'],
                            if ((c['card_number'] ?? '').isNotEmpty)
                              '#${c['card_number']}',
                          ].whereType<String>().join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.add_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
