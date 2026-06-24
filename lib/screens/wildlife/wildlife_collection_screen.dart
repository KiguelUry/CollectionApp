import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_category.dart';
import '../../models/collection_item.dart';
import '../../services/inaturalist_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/collection_cover_image.dart';
import '../../widgets/category_hub_header.dart';
import 'wildlife_map_screen.dart';
import 'wildlife_species_screen.dart';

/// Hub Pokédex sauvage (iNaturalist + observations).
class WildlifeCollectionScreen extends StatefulWidget {
  const WildlifeCollectionScreen({super.key});

  @override
  State<WildlifeCollectionScreen> createState() =>
      _WildlifeCollectionScreenState();
}

class _WildlifeCollectionScreenState extends State<WildlifeCollectionScreen> {
  static final _accent = CollectionCategory.wildlife.color;
  WildlifeKingdom? _filter;
  List<CollectionItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  List<CollectionItem> get _filtered {
    if (_filter == null) return _items;
    final k = _filter!.dbValue;
    return _items
        .where((i) => i.metadata?['wildlife_kingdom'] == k)
        .toList();
  }

  double get _completion {
    if (_items.isEmpty) return 0;
    final withObs = _items.where((i) => (i.gamesPlayed ?? 0) > 0).length;
    return withObs / _items.length;
  }

  Future<void> _addSpecies() async {
    final controller = TextEditingController();
    final hit = await showDialog<WildlifeTaxonHit>(
      context: context,
      builder: (ctx) => _INatSearchDialog(controller: controller),
    );
    if (hit == null || !mounted) return;

    try {
      await ProfileService().ensureCurrentUserProfile();
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('collection_items').insert({
        'title': hit.displayTitle,
        'category': CollectionCategory.wildlife.dbValue,
        'image_url': hit.imageUrl,
        'metadata': hit.toItemMetadata(),
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryHubHeader(
            title: 'Pokédex sauvage',
            accentColor: _accent,
            trailingActions: [
              IconButton(
                icon: Icon(Icons.map_outlined, color: Colors.white),
                tooltip: 'Carte',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WildlifeMapScreen(),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _completion,
                          minHeight: 10,
                          backgroundColor: _accent.withValues(alpha: 0.15),
                          color: _accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(_completion * 100).round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Espèces observées au moins une fois',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      FilterChip(
                        label: const Text('Tous'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      const SizedBox(width: 6),
                      for (final k in WildlifeKingdom.values)
                        if (k != WildlifeKingdom.other) ...[
                          FilterChip(
                            label: Text(k.label),
                            selected: _filter == k,
                            onSelected: (_) => setState(() => _filter = k),
                          ),
                          const SizedBox(width: 6),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Aucune espèce — ajoute ton premier Pokémon IRL !',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          final kingdom = WildlifeKingdom.fromDb(
                            item.metadata?['wildlife_kingdom'] as String?,
                          );
                          return InkWell(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      WildlifeSpeciesScreen(item: item),
                                ),
                              );
                              _load();
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: item.imageUrl != null
                                        ? CollectionCoverImage(
                                            url: item.imageUrl!,
                                            fit: BoxFit.cover,
                                          )
                                        : ColoredBox(
                                            color: _accent.withValues(
                                              alpha: 0.12,
                                            ),
                                            child: Icon(
                                              Icons.pets,
                                              size: 48,
                                              color: _accent,
                                            ),
                                          ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (kingdom != null)
                                          Text(
                                            kingdom.label,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSpecies,
        backgroundColor: _accent,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle espèce'),
      ),
    );
  }
}

class _INatSearchDialog extends StatefulWidget {
  final TextEditingController controller;

  const _INatSearchDialog({required this.controller});

  @override
  State<_INatSearchDialog> createState() => _INatSearchDialogState();
}

class _INatSearchDialogState extends State<_INatSearchDialog> {
  List<WildlifeTaxonHit> _hits = [];
  bool _searching = false;

  Future<void> _search() async {
    setState(() => _searching = true);
    final hits =
        await INaturalistService.searchSpecies(widget.controller.text);
    if (mounted) {
      setState(() {
        _hits = hits;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chercher sur iNaturalist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Léopard, mésange, papillon…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_searching)
              const LinearProgressIndicator()
            else
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (context, i) {
                    final h = _hits[i];
                    return ListTile(
                      leading: h.imageUrl != null
                          ? Image.network(h.imageUrl!, width: 48, height: 48,
                              fit: BoxFit.cover)
                          : const Icon(Icons.pets),
                      title: Text(h.displayTitle),
                      subtitle: Text(h.name, maxLines: 1),
                      onTap: () => Navigator.pop(context, h),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}
