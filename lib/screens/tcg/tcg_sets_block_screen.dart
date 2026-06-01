import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/user_card_collection_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/bgg_network_image.dart';
import 'tcg_set_cards_screen.dart';

/// Séries d'un bloc (logos + codes type BLK, SVI…).
class TcgSetsBlockScreen extends StatefulWidget {
  final CardSubcategory subcategory;
  final TcgSeriesBlock block;

  const TcgSetsBlockScreen({
    super.key,
    required this.subcategory,
    required this.block,
  });

  @override
  State<TcgSetsBlockScreen> createState() => _TcgSetsBlockScreenState();
}

class _TcgSetsBlockScreenState extends State<TcgSetsBlockScreen> {
  Set<String> _ownedSetIds = {};

  @override
  void initState() {
    super.initState();
    _loadOwned();
  }

  Future<void> _loadOwned() async {
    final owned =
        await UserCardCollectionService().ownedSetCodes(widget.subcategory);
    if (mounted) setState(() => _ownedSetIds = owned);
  }

  bool _hasSet(TcgSetInfo set) {
    return _ownedSetIds.contains(set.id) ||
        (set.code != null && _ownedSetIds.contains(set.code));
  }

  int get _ownedCount =>
      widget.block.sets.where(_hasSet).length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppAppBar(title: widget.block.displayName),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.block.sets.length} séries',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (_ownedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_ownedCount dans ta collection',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final set = widget.block.sets[i];
                  final owned = _hasSet(set);
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 280 + i * 25),
                    curve: Curves.easeOut,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.scale(scale: 0.92 + 0.08 * value, child: child),
                    ),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => TcgSetCardsScreen(
                                subcategory: widget.subcategory,
                                set: set,
                              ),
                            ),
                          ).then((_) => _loadOwned());
                        },
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: set.imageUrl != null &&
                                            set.imageUrl!.isNotEmpty
                                        ? BggNetworkImage(url: set.imageUrl!)
                                        : ColoredBox(
                                            color: widget.subcategory.color
                                                .withValues(alpha: 0.08),
                                            child: Icon(
                                              Icons.style,
                                              size: 48,
                                              color: widget.subcategory.color,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    set.displayName,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    set.displaySubtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (owned)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade600,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: widget.block.sets.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
