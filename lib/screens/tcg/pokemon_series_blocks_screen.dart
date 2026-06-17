import 'package:flutter/material.dart';

import '../../models/card_subcategory.dart';
import '../../models/collection_category.dart';
import '../../models/pokemon_card_lang.dart';
import '../../models/tcg_set_info.dart';
import '../../services/pokemon_tcg_service.dart';
import '../../services/user_card_collection_service.dart';
import '../../utils/app_haptics.dart';
import '../../utils/collection_grid_layout.dart';
import '../home_screen.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/tcg/tcg_set_logo.dart';
import '../../widgets/ui/loading_placeholder.dart';
import 'tcg_sets_block_screen.dart';

/// Blocs Pokémon regroupés par langue TCGdex (FR / EN / JA).
class PokemonSeriesBlocksScreen extends StatefulWidget {
  const PokemonSeriesBlocksScreen({super.key});

  @override
  State<PokemonSeriesBlocksScreen> createState() =>
      _PokemonSeriesBlocksScreenState();
}

class _PokemonSeriesBlocksScreenState extends State<PokemonSeriesBlocksScreen> {
  static const _sub = CardSubcategory.pokemon;

  final Map<String, List<TcgSeriesBlock>> _blocksByLang = {};
  final Map<String, bool> _expanded = {
    PokemonCardLang.fr: true,
    PokemonCardLang.en: false,
    PokemonCardLang.ja: false,
  };
  final Map<String, bool> _loadingLang = {};
  Set<String> _ownedSetIds = {};
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLang(PokemonCardLang.fr);
    _refreshOwned();
  }

  Future<void> _refreshOwned() async {
    final owned = await UserCardCollectionService().ownedSetCodes(_sub);
    if (mounted) setState(() => _ownedSetIds = owned);
  }

  Future<void> _loadLang(String lang) async {
    if (_blocksByLang.containsKey(lang) || _loadingLang[lang] == true) return;
    setState(() {
      _loadingLang[lang] = true;
      _error = null;
    });
    try {
      final blocks = await PokemonTcgService.fetchBlocks(lang: lang);
      if (!mounted) return;
      setState(() {
        _blocksByLang[lang] = blocks;
        _loadingLang[lang] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLang[lang] = false;
        _error = '$e';
      });
    }
  }

  List<TcgSeriesBlock> _visibleBlocks(String lang) {
    final list = _blocksByLang[lang] ?? [];
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
        title: _sub.label,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => const HomeScreen(
                    category: CollectionCategory.card,
                    screenTitle: 'Pokémon',
                    fixedCardSubcategory: _sub,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('Ma collection'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _blocksByLang.clear();
          for (final lang in PokemonCardLang.all) {
            if (_expanded[lang] == true) await _loadLang(lang);
          }
          await _refreshOwned();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Blocs et séries par langue — chaque langue a son propre catalogue TCGdex.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Rechercher un bloc…',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 20),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ),
            for (final lang in PokemonCardLang.all)
              SliverToBoxAdapter(
                child: _LangSection(
                  lang: lang,
                  expanded: _expanded[lang] ?? false,
                  loading: _loadingLang[lang] == true,
                  blocks: _visibleBlocks(lang),
                  ownedInBlock: _ownedInBlock,
                  onExpansionChanged: (open) {
                    setState(() => _expanded[lang] = open);
                    if (open) _loadLang(lang);
                  },
                  onBlockTap: (block) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => TcgSetsBlockScreen(
                          subcategory: _sub,
                          block: block,
                          tcgLang: lang,
                        ),
                      ),
                    ).then((_) => _refreshOwned());
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _LangSection extends StatelessWidget {
  final String lang;
  final bool expanded;
  final bool loading;
  final List<TcgSeriesBlock> blocks;
  final int Function(TcgSeriesBlock) ownedInBlock;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(TcgSeriesBlock block) onBlockTap;

  const _LangSection({
    required this.lang,
    required this.expanded,
    required this.loading,
    required this.blocks,
    required this.ownedInBlock,
    required this.onExpansionChanged,
    required this.onBlockTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onExpansionChanged,
          leading: CircleAvatar(
            backgroundColor: CardSubcategory.pokemon.color.withValues(alpha: 0.15),
            child: Text(
              PokemonCardLang.shortLabel(lang),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: CardSubcategory.pokemon.color,
              ),
            ),
          ),
          title: Text(
            PokemonCardLang.label(lang),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: loading
              ? const Text('Chargement…', style: TextStyle(fontSize: 11))
              : Text(
                  blocks.isEmpty
                      ? 'Aucun bloc'
                      : '${blocks.length} bloc${blocks.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: LoadingPlaceholder(grid: false, count: 2),
              )
            else if (blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Catalogue vide pour cette langue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: CollectionGridLayout.gridDelegate(
                    context,
                    mobileColumns: 2,
                    childAspectRatio: 0.92,
                    spacing: 10,
                  ),
                  itemCount: blocks.length,
                  itemBuilder: (context, i) {
                    final block = blocks[i];
                    return _BlockCard(
                      block: block,
                      ownedCount: ownedInBlock(block),
                      onTap: () {
                        AppHaptics.selection();
                        onBlockTap(block);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final TcgSeriesBlock block;
  final int ownedCount;
  final VoidCallback onTap;

  const _BlockCard({
    required this.block,
    required this.ownedCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = CardSubcategory.pokemon.color;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Expanded(
                child: TcgSetLogo.forBlock(
                  subcategory: CardSubcategory.pokemon,
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
