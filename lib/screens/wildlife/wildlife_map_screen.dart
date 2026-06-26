import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../models/wildlife_taxonomy.dart';
import '../../services/wildlife_service.dart';
import '../../theme/wildlife_pokedex_theme.dart';

class WildlifeMapScreen extends StatefulWidget {
  const WildlifeMapScreen({super.key});

  @override
  State<WildlifeMapScreen> createState() => _WildlifeMapScreenState();
}

class _WildlifeMapScreenState extends State<WildlifeMapScreen> {
  final _service = WildlifeService();
  List<WildlifeMapPoint> _points = [];
  List<WildlifeRealmStat> _realmStats = [];
  WildlifeRealm? _filterRealm;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final points = await _service.fetchMapPoints();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    var items = <CollectionItem>[];
    if (userId != null) {
      final rows = await Supabase.instance.client
          .from('collection_items')
          .select()
          .or('added_by.eq.$userId,location_user_id.eq.$userId')
          .eq('category', CollectionCategory.wildlife.dbValue)
          .eq('is_wishlist', false);
      items = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _points = points;
      _realmStats = _service.realmStatsFromItems(items);
      _loading = false;
    });
  }

  List<WildlifeMapPoint> get _visiblePoints {
    if (_filterRealm == null) return _points;
    return _points.where((p) => p.realm == _filterRealm).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte sauvage'),
        backgroundColor: WildlifePokedexTheme.panel,
        foregroundColor: WildlifePokedexTheme.neon,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildMap(),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _buildRealmPanel(),
                ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    final visible = _visiblePoints;
    final center = visible.isNotEmpty
        ? LatLng(
            visible.first.observation.latitude!,
            visible.first.observation.longitude!,
          )
        : const LatLng(46.5, 2.5);

    if (visible.isEmpty && _points.isNotEmpty) {
      return const Center(
        child: Text('Aucun point pour ce règne.'),
      );
    }

    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aucune observation géolocalisée.\nAjoute une observation avec GPS depuis une fiche espèce.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WildlifePokedexTheme.text.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: visible.length == 1 ? 11 : 6,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.collectingo.app',
        ),
        MarkerLayer(
          markers: [
            for (final p in visible)
              Marker(
                point: LatLng(
                  p.observation.latitude!,
                  p.observation.longitude!,
                ),
                width: 44,
                height: 44,
                child: Tooltip(
                  message: '${p.speciesTitle}\n${p.realm.label}',
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.realm.color.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(blurRadius: 6, color: Colors.black38),
                      ],
                    ),
                    child: Icon(
                      p.realm.icon,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRealmPanel() {
    final pointCounts = <WildlifeRealm, int>{};
    for (final p in _points) {
      pointCounts[p.realm] = (pointCounts[p.realm] ?? 0) + 1;
    }

    final speciesCounts = {
      for (final s in _realmStats) s.realm: s.speciesCount,
    };

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: WildlifePokedexTheme.panel.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PAR RÈGNE',
              style: WildlifePokedexTheme.titleStyle(context).copyWith(
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Tous'),
                  selected: _filterRealm == null,
                  onSelected: (_) => setState(() => _filterRealm = null),
                ),
                for (final r in WildlifeRealm.values)
                  if ((pointCounts[r] ?? 0) > 0 ||
                      (speciesCounts[r] ?? 0) > 0)
                    FilterChip(
                      avatar: Icon(r.icon, size: 16, color: r.color),
                      label: Text(
                        '${r.label} · ${speciesCounts[r] ?? 0} esp. · ${pointCounts[r] ?? 0} pts',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _filterRealm == r,
                      onSelected: (_) => setState(
                        () => _filterRealm = _filterRealm == r ? null : r,
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
