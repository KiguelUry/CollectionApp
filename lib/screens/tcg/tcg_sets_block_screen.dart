import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/tcg_set_info.dart';
import '../../services/user_card_collection_service.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/tcg/tcg_set_logo.dart';
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
  Map<String, int> _ownedCounts = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadOwned();
  }

  Future<void> _loadOwned() async {
    final counts =
        await UserCardCollectionService().ownedCountsBySet(widget.subcategory);
    if (mounted) setState(() => _ownedCounts = counts);
  }

  int _ownedInSet(TcgSetInfo set) =>
      UserCardCollectionService().ownedInSet(_ownedCounts, set);

  int get _ownedCount =>
      widget.block.sets.where((s) => _ownedInSet(s) > 0).length;

  List<TcgSetInfo> get _visibleSets {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.block.sets;
    return widget.block.sets
        .where(
          (s) =>
              s.displayName.toLowerCase().contains(q) ||
              (s.code?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleSets = _visibleSets;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Rechercher une série…',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                children: [
                  Expanded(
                    child: Text(
                      '${visibleSets.length} / ${widget.block.sets.length} séries',
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
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            sliver: visibleSets.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Aucune série ne correspond à la recherche.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final set = visibleSets[i];
                  final ownedCount = _ownedInSet(set);
                  final total = set.totalCards ?? 0;
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
                                    child: TcgSetLogo.forSet(
                                      subcategory: widget.subcategory,
                                      set: set,
                                      fallbackColor: widget.subcategory.color,
                                      fallbackLabel: set.code?.toUpperCase() ??
                                          (set.id.length > 3
                                              ? set.id.substring(0, 3)
                                              : set.id),
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
                            if (ownedCount > 0)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade700,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    total > 0
                                        ? '$ownedCount/$total'
                                        : '$ownedCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: visibleSets.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
