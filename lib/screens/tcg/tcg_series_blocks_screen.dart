import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/user_card_collection_service.dart';
import '../../utils/app_haptics.dart';
import '../../widgets/app_app_bar.dart';
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

  int _ownedInBlock(TcgSeriesBlock block) {
    return block.sets.where((s) {
      return _ownedSetIds.contains(s.id) ||
          (s.code != null && _ownedSetIds.contains(s.code));
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: widget.subcategory.label),
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
              : _blocks!.isEmpty
                  ? EmptyState(
                      icon: Icons.layers_outlined,
                      title: 'Aucun bloc',
                      message: 'Le catalogue n\'a rien renvoyé pour cet univers.',
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
                          child: Text(
                            'Choisis un bloc',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 132,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _blocks!.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              final block = _blocks![i];
                              final owned = _ownedInBlock(block);
                              return _BlockChip(
                                label: block.displayName,
                                subtitle:
                                    '${block.sets.length} séries${owned > 0 ? ' · $owned chez toi' : ''}',
                                color: widget.subcategory.color,
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
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.4,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final block = _blocks![i];
                              return _BlockCard(
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
                            childCount: _blocks!.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _BlockChip({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 200,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final TcgSeriesBlock block;
  final Color color;
  final int ownedCount;
  final VoidCallback onTap;

  const _BlockCard({
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
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.layers, color: color),
              const Spacer(),
              Text(
                block.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${block.sets.length} séries'
                '${ownedCount > 0 ? ' · ♥ $ownedCount' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
