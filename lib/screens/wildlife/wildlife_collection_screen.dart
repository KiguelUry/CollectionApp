import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../models/wildlife_catalog.dart';
import '../../models/wildlife_taxonomy.dart';
import '../../services/inaturalist_service.dart';
import '../../services/profile_service.dart';
import '../../theme/wildlife_pokedex_theme.dart';
import '../../widgets/collection_cover_image.dart';
import '../../widgets/wildlife/inat_search_dialog.dart';
import '../../widgets/wildlife/pokedex_stats_panel.dart';
import 'wildlife_map_screen.dart';
import 'wildlife_species_screen.dart';

enum _PokedexLevel { realm, animalGroup, family, genusGroup, species }

/// Console Pokédex — 5 règnes, groupes animaux, familles vedettes + Autre, stats terrain.
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

  WildlifeRealm? _realm;
  WildlifeKingdom? _animalGroup;
  String? _familyId;
  String? _genusGroupId;

  _PokedexLevel get _level {
    if (_genusGroupId != null) return _PokedexLevel.species;
    if (_familyId != null) return _PokedexLevel.genusGroup;
    if (_animalGroup != null) return _PokedexLevel.family;
    if (_realm == WildlifeRealm.animalia) return _PokedexLevel.animalGroup;
    if (_realm != null) return _PokedexLevel.species;
    return _PokedexLevel.realm;
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
    if (_realm != null) {
      final r = _realm!.dbValue;
      list = list.where(
        (i) =>
            WildlifeRealm.fromDb(i.metadata?['wildlife_realm'] as String?)
                .dbValue ==
            r,
      );
    }
    if (_animalGroup != null) {
      final k = _animalGroup!.dbValue;
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

  PokedexStats get _stats => PokedexStats.fromItems(_items);

  int _countRealm(WildlifeRealm r) => _items
      .where(
        (i) =>
            WildlifeRealm.fromDb(i.metadata?['wildlife_realm'] as String?) ==
            r,
      )
      .length;

  int _countAnimalGroup(WildlifeKingdom k) => _items
      .where((i) => i.metadata?['wildlife_kingdom'] == k.dbValue)
      .length;

  int _countForFamily(String familyId) {
    if (_animalGroup == null) return 0;
    return _items
        .where((i) =>
            i.metadata?['wildlife_kingdom'] == _animalGroup!.dbValue &&
            (i.metadata?['wildlife_family'] as String? ?? 'other') == familyId)
        .length;
  }

  int _countForGenusGroup(String groupId) {
    if (_animalGroup == null || _familyId == null) return 0;
    return _items
        .where((i) =>
            i.metadata?['wildlife_kingdom'] == _animalGroup!.dbValue &&
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
          if (_realm != WildlifeRealm.animalia) {
            _realm = null;
          } else {
            _genusGroupId = null;
          }
        case _PokedexLevel.genusGroup:
          _familyId = null;
        case _PokedexLevel.family:
          _animalGroup = null;
        case _PokedexLevel.animalGroup:
          _realm = null;
        case _PokedexLevel.realm:
          break;
      }
    });
  }

  Future<void> _pickExtraTaxon({
    required String title,
    required List<WildlifeTaxonNode> options,
    required void Function(String id) onPick,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WildlifePokedexTheme.panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: WildlifePokedexTheme.neon,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options
                    .map(
                      (n) => ListTile(
                        leading: Icon(n.icon, color: n.color),
                        title: Text(
                          n.label,
                          style: const TextStyle(color: WildlifePokedexTheme.text),
                        ),
                        onTap: () => Navigator.pop(ctx, n.id),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }

  void _onFamilyTap(String id) {
    if (id == WildlifeTaxonomy.otherFamilyId && _animalGroup != null) {
      final extras = WildlifeTaxonomy.extraFamilies(_animalGroup!);
      if (extras.isEmpty) return;
      _pickExtraTaxon(
        title: 'Choisir une famille',
        options: extras,
        onPick: (picked) => setState(() => _familyId = picked),
      );
    } else {
      setState(() => _familyId = id);
    }
  }

  void _onGenusTap(String id) {
    if (id == WildlifeTaxonomy.otherGenusGroupId && _familyId != null) {
      final extras = WildlifeTaxonomy.extraGenusGroups(_familyId!);
      if (extras.isEmpty) {
        setState(() => _genusGroupId = id);
        return;
      }
      _pickExtraTaxon(
        title: 'Choisir un groupe',
        options: extras,
        onPick: (picked) => setState(() => _genusGroupId = picked),
      );
    } else {
      setState(() => _genusGroupId = id);
    }
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
        _PokedexLevel.realm => 'Les 5 règnes du vivant',
        _PokedexLevel.animalGroup => 'Groupes · Règne animal',
        _PokedexLevel.family => 'Familles · ${_animalGroup!.label}',
        _PokedexLevel.genusGroup =>
          WildlifeTaxonomy.familyLabel(_familyId, _animalGroup!) ?? 'Famille',
        _PokedexLevel.species => _genusGroupId != null && _familyId != null
            ? (WildlifeTaxonomy.genusGroupLabel(_familyId!, _genusGroupId!) ??
                'Espèces')
            : '${_realm?.label ?? 'Règne'} · observations',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WildlifePokedexTheme.bg,
      body: DecoratedBox(
        decoration: WildlifePokedexTheme.screenDecoration(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              if (_level != _PokedexLevel.realm) _buildBreadcrumb(),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_level != _PokedexLevel.realm)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: WildlifePokedexTheme.neon),
              onPressed: _popLevel,
            )
          else if (Navigator.canPop(context))
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: WildlifePokedexTheme.neon),
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
                const SizedBox(height: 8),
                PokedexStatsPanel(stats: _stats),
              ],
            ),
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
        .fadeIn(duration: 500.ms);
  }

  Widget _buildBreadcrumb() {
    final parts = <String>[];
    if (_realm != null) parts.add(_realm!.label);
    if (_animalGroup != null) parts.add(_animalGroup!.label);
    if (_familyId != null && _animalGroup != null) {
      parts.add(
        WildlifeTaxonomy.familyLabel(_familyId, _animalGroup!) ?? '…',
      );
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
      _PokedexLevel.realm => _realmGrid(),
      _PokedexLevel.animalGroup => _animalGroupGrid(),
      _PokedexLevel.family => _taxonGrid(
          WildlifeTaxonomy.featuredFamilies(_animalGroup!),
          _countForFamily,
          _onFamilyTap,
        ),
      _PokedexLevel.genusGroup => _taxonGrid(
          WildlifeTaxonomy.featuredGenusGroups(_familyId!),
          _countForGenusGroup,
          _onGenusTap,
        ),
      _PokedexLevel.species => _speciesContent(),
    };
  }

  Widget _realmGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.95,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: WildlifeRealm.values.length,
      itemBuilder: (context, i) {
        final r = WildlifeRealm.values[i];
        return _TaxonTile(
          label: r.label,
          subtitle: r.subtitle,
          count: _countRealm(r),
          countLabel: 'fiches',
          icon: r.icon,
          color: r.color,
          delayMs: i * 60,
          entered: _entered,
          onTap: () => setState(() => _realm = r),
        );
      },
    );
  }

  Widget _animalGroupGrid() {
    final groups =
        WildlifeKingdom.values.where((k) => k != WildlifeKingdom.other);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final k = groups.elementAt(i);
        return _TaxonTile(
          label: k.label,
          count: _countAnimalGroup(k),
          countLabel: 'espèces',
          icon: _animalIcon(k),
          color: WildlifePokedexTheme.neon,
          delayMs: i * 50,
          entered: _entered,
          onTap: () => setState(() => _animalGroup = k),
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
          countLabel: 'espèces',
          icon: n.icon,
          color: n.color,
          delayMs: i * 50,
          entered: _entered,
          onTap: () => onTap(n.id),
        );
      },
    );
  }

  Widget _speciesContent() {
    final list = _scopedItems;
    final catalog = _genusGroupId != null
        ? WildlifeCatalog.featuredForGenusGroup(_genusGroupId!)
        : const <WildlifeCatalogEntry>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (catalog.isNotEmpty) ...[
          Text(
            'ESPÈCES CONNUES',
            style: WildlifePokedexTheme.titleStyle(context).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: catalog.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _catalogCard(catalog[i]),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          'TES OBSERVATIONS',
          style: WildlifePokedexTheme.titleStyle(context).copyWith(fontSize: 14),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: WildlifePokedexTheme.tileDecoration(),
            child: Text(
              'Aucune espèce ici — scanne un spécimen avec iNaturalist !',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WildlifePokedexTheme.text.withValues(alpha: 0.65),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => _speciesCard(list[i], i),
          ),
      ],
    );
  }

  Widget _catalogCard(WildlifeCatalogEntry entry) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: WildlifePokedexTheme.panel,
          title: Text(entry.label,
              style: const TextStyle(color: WildlifePokedexTheme.neon)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      entry.imageUrl!,
                      height: 120,
                      width: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 0),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  entry.description,
                  style: TextStyle(
                    color: WildlifePokedexTheme.text.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
      child: Container(
        width: 140,
        decoration: WildlifePokedexTheme.tileDecoration(
          glow: WildlifePokedexTheme.accent,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: entry.imageUrl != null
                  ? Image.network(
                      entry.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 40),
                    )
                  : ColoredBox(
                      color: WildlifePokedexTheme.panel,
                      child: Icon(
                        Icons.menu_book,
                        color: WildlifePokedexTheme.text.withValues(alpha: 0.4),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                entry.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WildlifePokedexTheme.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _speciesCard(CollectionItem item, int index) {
    final unlocked = (item.gamesPlayed ?? 0) > 0;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WildlifeSpeciesScreen(item: item)),
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
                              Colors.transparent, BlendMode.dst)
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
                      child: const Icon(Icons.pets, size: 48,
                          color: WildlifePokedexTheme.neon),
                    ),
                  if (!unlocked)
                    Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: const Icon(Icons.lock_outline,
                          color: Colors.white70, size: 32),
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
                        ? '${item.gamesPlayed} observation${(item.gamesPlayed ?? 0) > 1 ? 's' : ''}'
                        : 'Pas encore observé',
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
        .fadeIn(delay: Duration(milliseconds: index * 40));
  }

  IconData _animalIcon(WildlifeKingdom k) => switch (k) {
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
  final String? subtitle;
  final int count;
  final String countLabel;
  final IconData icon;
  final Color color;
  final int delayMs;
  final bool entered;
  final VoidCallback onTap;

  const _TaxonTile({
    required this.label,
    this.subtitle,
    required this.count,
    required this.countLabel,
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
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: WildlifePokedexTheme.text.withValues(alpha: 0.55),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '$count $countLabel',
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
