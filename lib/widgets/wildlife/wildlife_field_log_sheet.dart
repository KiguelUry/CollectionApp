import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_item.dart';
import '../../services/wildlife_service.dart';
import '../../theme/wildlife_pokedex_theme.dart';
import '../../widgets/collection_cover_image.dart';
import '../../screens/wildlife/wildlife_species_screen.dart';

/// Journal rapide de sortie terrain (+1 observation sur une espèce connue).
Future<void> showWildlifeFieldLogSheet(
  BuildContext context, {
  required List<CollectionItem> species,
  required VoidCallback onLogged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WildlifePokedexTheme.panel,
    showDragHandle: true,
    builder: (ctx) => _WildlifeFieldLogSheet(
      species: species,
      onLogged: onLogged,
    ),
  );
}

class _WildlifeFieldLogSheet extends StatefulWidget {
  final List<CollectionItem> species;
  final VoidCallback onLogged;

  const _WildlifeFieldLogSheet({
    required this.species,
    required this.onLogged,
  });

  @override
  State<_WildlifeFieldLogSheet> createState() => _WildlifeFieldLogSheetState();
}

class _WildlifeFieldLogSheetState extends State<_WildlifeFieldLogSheet> {
  final _service = WildlifeService();
  String? _loggingId;

  List<CollectionItem> get _recentSpecies {
    final sorted = List<CollectionItem>.from(widget.species);
    sorted.sort((a, b) {
      final ao = a.gamesPlayed ?? 0;
      final bo = b.gamesPlayed ?? 0;
      if (ao != bo) return bo.compareTo(ao);
      return a.title.compareTo(b.title);
    });
    return sorted.take(12).toList();
  }

  Future<void> _quickLog(CollectionItem item) async {
    setState(() => _loggingId = item.id);
    try {
      await _service.addObservation(
        itemId: item.id,
        observedAt: DateTime.now(),
      );
      final obs = await _service.fetchForItem(item.id);
      await Supabase.instance.client.from('collection_items').update({
        'games_played': obs.length,
      }).eq('id', item.id);

      if (!mounted) return;
      widget.onLogged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Observation enregistrée · ${item.title}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _loggingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recentSpecies;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sortie terrain',
              style: WildlifePokedexTheme.titleStyle(context),
            ),
            const SizedBox(height: 6),
            Text(
              'Tape une espèce pour enregistrer une observation rapide.',
              style: TextStyle(
                fontSize: 13,
                color: WildlifePokedexTheme.text.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (recent.isEmpty)
              Text(
                'Ajoute d\'abord des espèces avec le scanner.',
                style: TextStyle(
                  color: WildlifePokedexTheme.text.withValues(alpha: 0.65),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = recent[i];
                    final obs = item.gamesPlayed ?? 0;
                    final busy = _loggingId == item.id;
                    return ListTile(
                      tileColor: WildlifePokedexTheme.bg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: WildlifePokedexTheme.neon.withValues(alpha: 0.35),
                        ),
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: item.imageUrl != null
                              ? CollectionCoverImage(
                                  url: item.imageUrl!,
                                  fit: BoxFit.cover,
                                )
                              : ColoredBox(
                                  color: WildlifePokedexTheme.neonDim
                                      .withValues(alpha: 0.3),
                                  child: const Icon(Icons.pets, size: 22),
                                ),
                        ),
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(
                          color: WildlifePokedexTheme.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        obs > 0 ? '$obs observation${obs > 1 ? 's' : ''}' : 'Jamais vu',
                        style: TextStyle(
                          fontSize: 12,
                          color: WildlifePokedexTheme.text.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Noter une observation',
                              onPressed: () => _quickLog(item),
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: WildlifePokedexTheme.neon,
                              ),
                            ),
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WildlifeSpeciesScreen(item: item),
                          ),
                        );
                        widget.onLogged();
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
