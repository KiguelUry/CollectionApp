import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../models/wildlife_taxonomy.dart';
import '../../services/inaturalist_service.dart';
import '../../services/profile_service.dart';
import '../../theme/wildlife_pokedex_theme.dart';
import '../../widgets/collection_cover_image.dart';
import '../../widgets/wildlife/inat_search_dialog.dart';
import '../../widgets/wildlife/pokedex_completion_ring.dart';
import 'wildlife_map_screen.dart';
import 'wildlife_species_screen.dart';

enum _PokedexLevel { kingdom, family, genusGroup, species }

/// Console Pokédex immersive — navigation taxonomique à 4 niveaux.
class WildlifeCollectionScreen extends StatefulWidget {
  const WildlifeCollectionScreen({super.key});

  @override
  State<WildlifeCollectionScreen> createState() =>
      _WildlifeCollectionScreenState();
}

class _WildlifeCollectionScreenState extends State<WildlifeCollectionScreen> {
  List<CollectionItem> _items = [];
  bool _loading = true;
  bool _entered = false;

  WildlifeKingdom? _kingdom;
  String? _familyId;
  String? _genusGroupId;

  _PokedexLevel get _level {
    if (_genusGroupId != null) return _PokedexLevel.species;
    if (_familyId != null) return _PokedexLevel.genusGroup;
    if (_kingdom != null) return _PokedexLevel.family;
    return _PokedexLevel.kingdom;
  }

  @override
  void initState() {
    super.initState();
    _load();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _entered = true);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final rows = await Supabase.instance.client
        .from('collection_items')
        .select()
        .or('added_by.eq.$userId,location_user_id.eq.$userId')
        .eq('category', CollectionCategory.wildlife.dbValue)
        .eq('is_wishlist', false)
        .order('title');
    final items = (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  List<CollectionItem> get _scopedItems {
    Iterable<CollectionItem> list = _items;
    if (_kingdom != null) {
      final k = _kingdom!.dbValue;
      list = list.where((i) => i.metadata?['wildlife_kingdom'] == k);
    }
    if (_familyId != null) {
      list = list.where(
        (i) =>
            ((i.metadata?['wildlife_family'] as String?) ?? 'other') ==
            _familyId,
      );
    }
    if (_genusGroupId != null) {
      list = list.where(
        (i) =>
            ((i.metadata?['wildlife_genus_group'] as String?) ?? 'other') ==
            _genusGroupId,
      );
    }
    return list.toList();
  }

  double get _completion {
    if (_items.isEmpty) return 0;
    final withObs = _items.where((i) => (i.gamesPlayed ?? 0) > 0).length;
    return withObs / _items.length;
  }

  int _countForKingdom(WildlifeKingdom k) =>
      _items.where((i) => i.metadata?['wildlife_kingdom'] == k.dbValue).length;

  int _countForFamily(String familyId) {
    if (_kingdom == null) return 0;
    return _items
        .where((i) =>
            i.metadata?['wildlife_kingdom'] == _kingdom!.dbValue &&
            (i.metadata?['wildlife_family'] as String? ?? 'other') ==
                familyId)
        .length;
  }

  int _countForGenusGroup(String groupId) {
    if (_kingdom == null || _familyId == null) return 0;
    return _items
        .where((i) =>
            i.metadata?['wildlife_kingdom'] == _kingdom!.dbValue &&
            (i.metadata?['wildlife_family'] as String? ?? 'other') ==
                _familyId &&
            (i.metadata?['wildlife_genus_group'] as String? ?? 'other') ==
                groupId)
        .length;
  }

  void _popLevel() {
    setState(() {
      switch (_level) {
        case _PokedexLevel.species:
          _genusGroupId = null;
        case _PokedexLevel.genusGroup:
          _familyId = null;
        case _PokedexLevel.family:
          _kingdom = null;
        case _PokedexLevel.kingdom:
          break;
      }
    });
  }

  Future<void> _addSpecies() async {
    final hit = await showDialog<WildlifeTaxonHit>(
      context: context,
      builder: (_) => const WildlifeINatSearchDialog(),
    );
    if (hit == null || !mounted) return;

    try {
      await ProfileService().ensureCurrentUserProfile();
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final full = await INaturalistService.fetchTaxon(hit.id) ?? hit;
      await Supabase.instance.client.from('collection_items').insert({
        'title': full.displayTitle,
        'category': CollectionCategory.wildlife.dbValue,
        'image_url': full.imageUrl,
        'metadata': full.toItemMetadata(),
        'added_by': userId,
        'location_user_id': userId,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  String get _levelTitle => switch (_level) {
        _PokedexLevel.kingdom => 'Choisis ton Règne',
        _PokedexLevel.family => 'Familles · ${_kingdom!.label}',
        _PokedexLevel.genusGroup =>
          WildlifeTaxonomy.familyLabel(_familyId, _kingdom!) ?? 'Famille',
        _PokedexLevel.species =>
          WildlifeTaxonomy.genusGroupLabel(_familyId!, _genusGroupId!) ??
              'Espèces',
      };

  @override
  Widget build(BuildContext context) {
    final observed =
        _items.where((i) => (i.gamesPlayed ?? 0) > 0).length;

    return Scaffold(
      backgroundColor: WildlifePokedexTheme.bg,
      body: DecoratedBox(
        decoration: WildlifePokedexTheme.screenDecoration(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(observed),
              if (_level != _PokedexLevel.kingdom) _buildBreadcrumb(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  _levelTitle.toUpperCase(),
                  style: WildlifePokedexTheme.titleStyle(context),
                )
                    .animate(target: _entered ? 1 : 0)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.15, end: 0),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: WildlifePokedexTheme.neon,
                        ),
                      )
                    : _buildLevelContent(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSpecies,
        backgroundColor: WildlifePokedexTheme.neon,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.radar),
        label: const Text(
          'SCANNER',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
    );
  }

  Widget _buildHeader(int observed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          if (_level != _PokedexLevel.kingdom)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: WildlifePokedexTheme.neon),
              onPressed: _popLevel,
            )
          else if (Navigator.canPop(context))
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: WildlifePokedexTheme.neon),
              onPressed: () => Navigator.maybePop(context),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POKÉDEX SAUVAGE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: WildlifePokedexTheme.accent,
                  ),
                ),
                Text(
                  '${_items.length} espèce${_items.length > 1 ? 's' : ''} enregistrée${_items.length > 1 ? 's' : ''}',
                  style: WildlifePokedexTheme.breadcrumbStyle(),
                ),
              ],
            ),
          ),
          PokedexCompletionRing(
            progress: _completion,
            speciesCount: _items.length,
            observedCount: observed,
          ),
          IconButton(
            tooltip: 'Carte sauvage',
            icon: const Icon(Icons.map_outlined, color: WildlifePokedexTheme.warn),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WildlifeMapScreen()),
            ),
          ),
        ],
      ),
    )
        .animate(target: _entered ? 1 : 0)
        .fadeIn(duration: 500.ms)
        .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
  }

  Widget _buildBreadcrumb() {
    final parts = <String>[];
    if (_kingdom != null) parts.add(_kingdom!.label);
    if (_familyId != null) {
      parts.add(WildlifeTaxonomy.familyLabel(_familyId, _kingdom!) ?? '…');
    }
    if (_genusGroupId != null && _familyId != null) {
      parts.add(
        WildlifeTaxonomy.genusGroupLabel(_familyId!, _genusGroupId!) ?? '…',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Text(parts.join(' › '), style: WildlifePokedexTheme.breadcrumbStyle()),
    );
  }

  Widget _buildLevelContent() {
    return switch (_level) {
      _PokedexLevel.kingdom => _kingdomGrid(),
      _PokedexLevel.family => _taxonGrid(
          WildlifeTaxonomy.familiesFor(_kingdom!),
          _countForFamily,
          (id) => setState(() => _familyId = id),
        ),
      _PokedexLevel.genusGroup => _taxonGrid(
          WildlifeTaxonomy.genusGroupsFor(_familyId!),
          _countForGenusGroup,
          (id) => setState(() => _genusGroupId = id),
        ),
      _PokedexLevel.species => _speciesGrid(),
    };
  }

  Widget _kingdomGrid() {
    final kingdoms =
        WildlifeKingdom.values.where((k) => k != WildlifeKingdom.other);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: kingdoms.length,
      itemBuilder: (context, i) {
        final k = kingdoms.elementAt(i);
        final count = _countForKingdom(k);
        return _TaxonTile(
          label: k.label,
          count: count,
          icon: _kingdomIcon(k),
          color: WildlifePokedexTheme.neon,
          delayMs: i * 60,
          entered: _entered,
          onTap: () => setState(() => _kingdom = k),
        );
      },
    );
  }

  Widget _taxonGrid(
    List<WildlifeTaxonNode> nodes,
    int Function(String id) countFor,
    void Function(String id) onTap,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: nodes.length,
      itemBuilder: (context, i) {
        final n = nodes[i];
        return _TaxonTile(
          label: n.label,
          count: countFor(n.id),
          icon: n.icon,
          color: n.color,
          delayMs: i * 50,
          entered: _entered,
          onTap: () => onTap(n.id),
        );
      },
    );
  }

  Widget _speciesGrid() {
    final list = _scopedItems;
    if (list.isEmpty) {
      return Center(
        child: Text(
          'Aucune espèce ici — scanne ton premier spécimen !',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: WildlifePokedexTheme.text.withValues(alpha: 0.65),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final unlocked = (item.gamesPlayed ?? 0) > 0;
        return GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WildlifeSpeciesScreen(item: item),
              ),
            );
            _load();
          },
          child: Container(
            decoration: WildlifePokedexTheme.tileDecoration(
              glow: unlocked ? WildlifePokedexTheme.neon : WildlifePokedexTheme.panel,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.imageUrl != null)
                        ColorFiltered(
                          colorFilter: unlocked
                              ? const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.dst,
                                )
                              : const ColorFilter.matrix([
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0, 0, 0, 1, 0,
                                ]),
                          child: CollectionCoverImage(
                            url: item.imageUrl!,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        ColoredBox(
                          color: WildlifePokedexTheme.neonDim.withValues(alpha: 0.3),
                          child: const Icon(Icons.pets, size: 48, color: WildlifePokedexTheme.neon),
                        ),
                      if (!unlocked)
                        Container(
                          color: Colors.black38,
                          alignment: Alignment.center,
                          child: const Icon(Icons.lock_outline, color: Colors.white70, size: 32),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: WildlifePokedexTheme.text,
                        ),
                      ),
                      Text(
                        unlocked
                            ? '${item.gamesPlayed} obs.'
                            : 'Non observé',
                        style: TextStyle(
                          fontSize: 11,
                          color: unlocked
                              ? WildlifePokedexTheme.neon
                              : WildlifePokedexTheme.text.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
            .animate(target: _entered ? 1 : 0)
            .fadeIn(delay: Duration(milliseconds: i * 40))
            .scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              delay: Duration(milliseconds: i * 40),
            );
      },
    );
  }

  IconData _kingdomIcon(WildlifeKingdom k) => switch (k) {
        WildlifeKingdom.mammal => Icons.pets,
        WildlifeKingdom.bird => Icons.flutter_dash,
        WildlifeKingdom.fish => Icons.water,
        WildlifeKingdom.reptileAmphibian => Icons.grass,
        WildlifeKingdom.insect => Icons.bug_report,
        WildlifeKingdom.other => Icons.hub,
      };
}

class _TaxonTile extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final int delayMs;
  final bool entered;
  final VoidCallback onTap;

  const _TaxonTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.delayMs,
    required this.entered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: WildlifePokedexTheme.tileDecoration(glow: color),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 36, color: color),
                const Spacer(),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: WildlifePokedexTheme.text,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count espèce${count > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(target: entered ? 1 : 0)
        .fadeIn(delay: Duration(milliseconds: delayMs))
        .slideY(begin: 0.12, end: 0, delay: Duration(milliseconds: delayMs));
  }
}
