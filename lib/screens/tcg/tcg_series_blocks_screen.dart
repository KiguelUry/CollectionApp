import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/user_card_collection_service.dart';
import '../../utils/app_haptics.dart';
import '../../models/collection_category.dart';
import '../home_screen.dart';
import '../../widgets/app_app_bar.dart';
import '../../screens/tcg/tcg_rarity_gallery_screen.dart';
import '../../widgets/tcg/tcg_set_logo.dart';
import '../../widgets/ui/empty_state.dart';
import '../../widgets/ui/loading_placeholder.dart';
import 'tcg_sets_block_screen.dart';

/// Blocs / ères horizontaux (ex. Écarlate et Violet, Platine…).
class TcgSeriesBlocksScreen extends StatefulWidget {
  final CardSubcategory subcategory;
  final Future<List<TcgSeriesBlock>> Function() loadBlocks;

  const TcgSeriesBlocksScreen({
    super.key,
    required this.subcategory,
    required this.loadBlocks,
  });

  @override
  State<TcgSeriesBlocksScreen> createState() => _TcgSeriesBlocksScreenState();
}

class _TcgSeriesBlocksScreenState extends State<TcgSeriesBlocksScreen> {
  List<TcgSeriesBlock>? _blocks;
  Set<String> _ownedSetIds = {};
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blocks = await widget.loadBlocks();
      final owned = await UserCardCollectionService().ownedSetCodes(widget.subcategory);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _ownedSetIds = owned;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  List<TcgSeriesBlock> get _visibleBlocks {
    final list = _blocks ?? [];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((b) => b.displayName.toLowerCase().contains(q))
        .toList();
  }

  int _ownedInBlock(TcgSeriesBlock block) {
    return block.sets.where((s) {
      return _ownedSetIds.contains(s.id) ||
          (s.code != null && _ownedSetIds.contains(s.code));
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: widget.subcategory.label,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => HomeScreen(
                    category: CollectionCategory.card,
                    screenTitle: widget.subcategory.label,
                    fixedCardSubcategory: widget.subcategory,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('Ma collection'),
          ),
          if (_blocks != null && _blocks!.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => TcgRarityGalleryScreen(
                      subcategory: widget.subcategory,
                      title: '${widget.subcategory.label} · raretés',
                      sets: _blocks!.expand((b) => b.sets).toList(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.star_outline),
              label: const Text('Par rareté'),
            ),
        ],
      ),
      body: _loading
          ? const LoadingPlaceholder()
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Catalogue indisponible',
                  message: _error,
                  actionLabel: 'Réessayer',
                  onAction: _load,
                  iconColor: widget.subcategory.color,
                )
              : _visibleBlocks.isEmpty
                  ? EmptyState(
                      icon: Icons.layers_outlined,
                      title: (_blocks == null || _blocks!.isEmpty)
                          ? 'Aucun bloc'
                          : 'Aucun résultat',
                      message: (_blocks == null || _blocks!.isEmpty)
                          ? 'Le catalogue n\'a rien renvoyé pour cet univers.'
                          : 'Essaie un autre nom de bloc.',
                      actionLabel: 'Actualiser',
                      onAction: _load,
                      iconColor: widget.subcategory.color,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Rechercher un bloc…',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.search, size: 20),
                                ),
                                onChanged: (v) => setState(() => _query = v),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.92,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final block = _visibleBlocks[i];
                                  return _BlockCard(
                                    subcategory: widget.subcategory,
                                    block: block,
                                    color: widget.subcategory.color,
                                    ownedCount: _ownedInBlock(block),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (ctx) => TcgSetsBlockScreen(
                                            subcategory: widget.subcategory,
                                            block: block,
                                          ),
                                        ),
                                      ).then((_) => _load());
                                    },
                                  );
                                },
                                childCount: _visibleBlocks.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final CardSubcategory subcategory;
  final TcgSeriesBlock block;
  final Color color;
  final int ownedCount;
  final VoidCallback onTap;

  const _BlockCard({
    required this.subcategory,
    required this.block,
    required this.color,
    required this.ownedCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: TcgSetLogo.forBlock(
                  subcategory: subcategory,
                  block: block,
                  fallbackColor: color,
                  fallbackLabel: block.displayName.length > 3
                      ? block.displayName.substring(0, 2).toUpperCase()
                      : block.displayName,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                block.displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                '${block.sets.length} séries'
                '${ownedCount > 0 ? ' · $ownedCount possédées' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
