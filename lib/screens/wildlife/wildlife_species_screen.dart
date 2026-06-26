import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_item.dart';
import '../../models/wildlife_observation.dart';
import '../../services/image_compression_service.dart';
import '../../services/wildlife_service.dart';
import '../../theme/wildlife_pokedex_theme.dart';
import '../../widgets/collection_cover_image.dart';

class WildlifeSpeciesScreen extends StatefulWidget {
  final CollectionItem item;

  const WildlifeSpeciesScreen({super.key, required this.item});

  @override
  State<WildlifeSpeciesScreen> createState() => _WildlifeSpeciesScreenState();
}

class _WildlifeSpeciesScreenState extends State<WildlifeSpeciesScreen> {
  final _service = WildlifeService();
  List<WildlifeObservation> _observations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _observations = await _service.fetchForItem(widget.item.id);
    _observations.sort((a, b) => b.observedAt.compareTo(a.observedAt));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addObservation() async {
    final noteController = TextEditingController();
    final placeController = TextEditingController();
    var useGps = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: WildlifePokedexTheme.panel,
          title: const Text(
            'Nouvelle session',
            style: TextStyle(color: WildlifePokedexTheme.neon),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: placeController,
                  decoration: const InputDecoration(
                    labelText: 'Lieu',
                    hintText: 'Parc, sentier, jardin…',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'Comportement, météo…',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Géolocaliser'),
                  value: useGps,
                  onChanged: (v) => setLocal(() => useGps = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: WildlifePokedexTheme.neon,
                foregroundColor: Colors.black,
              ),
              child: const Text('Capturer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    double? lat;
    double? lng;
    if (useGps) {
      try {
        final pos = await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
    }

    String? photoUrl;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: true,
      );
      if (picked != null) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Compression et envoi…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final raw = await picked.readAsBytes();
        final bytes = await ImageCompressionService.compressForUpload(raw);
        final path =
            '${Supabase.instance.client.auth.currentUser!.id}/wildlife/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        photoUrl =
            Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    await _service.addObservation(
      itemId: widget.item.id,
      observedAt: DateTime.now(),
      note: noteController.text,
      placeLabel: placeController.text,
      latitude: lat,
      longitude: lng,
      photoUrl: photoUrl,
    );

    final wasFirstCapture = _observations.isEmpty;
    final count = _observations.length + 1;
    await Supabase.instance.client.from('collection_items').update({
      'games_played': count,
    }).eq('id', widget.item.id);

    await _load();

    if (mounted && wasFirstCapture) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: WildlifePokedexTheme.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: WildlifePokedexTheme.neon, width: 3),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: WildlifePokedexTheme.neon),
              const SizedBox(width: 8),
              const Text(
                'CAPTURE RÉUSSIE !',
                style: TextStyle(
                  color: WildlifePokedexTheme.neon,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          content: Text(
            '${widget.item.title} rejoint ton Pokédex.\n'
            '${photoUrl != null ? 'Photo HD enregistrée.' : 'Ajoute une photo lors de ta prochaine sortie !'}',
            style: const TextStyle(color: WildlifePokedexTheme.text),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: WildlifePokedexTheme.neon,
                foregroundColor: Colors.black,
              ),
              child: const Text('Génial !'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.item.metadata ?? {};
    final desc = meta['description'] as String?;
    final scientific = meta['scientific_name'] as String?;
    final unlocked = _observations.isNotEmpty;

    return Scaffold(
      backgroundColor: WildlifePokedexTheme.bg,
      body: DecoratedBox(
        decoration: WildlifePokedexTheme.screenDecoration(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: WildlifePokedexTheme.panel,
              foregroundColor: WildlifePokedexTheme.neon,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  widget.item.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.item.imageUrl != null)
                      CollectionCoverImage(
                        url: widget.item.imageUrl!,
                        fit: BoxFit.cover,
                      )
                    else
                      ColoredBox(
                        color: WildlifePokedexTheme.neonDim.withValues(alpha: 0.4),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            WildlifePokedexTheme.bg.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (scientific != null)
                      Text(
                        scientific,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: WildlifePokedexTheme.text.withValues(alpha: 0.75),
                        ),
                      ),
                    if (desc != null && desc.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        desc,
                        style: TextStyle(
                          color: WildlifePokedexTheme.text.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(
                          unlocked ? Icons.verified : Icons.lock_outline,
                          color: unlocked
                              ? WildlifePokedexTheme.neon
                              : WildlifePokedexTheme.text.withValues(alpha: 0.4),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unlocked ? 'ESPÈCE DÉBLOQUÉE' : 'EN ATTENTE D\'OBSERVATION',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            fontSize: 12,
                            color: unlocked
                                ? WildlifePokedexTheme.neon
                                : WildlifePokedexTheme.text.withValues(alpha: 0.5),
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: _addObservation,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                WildlifePokedexTheme.neon.withValues(alpha: 0.15),
                            foregroundColor: WildlifePokedexTheme.neon,
                          ),
                          icon: const Icon(Icons.add_a_photo, size: 18),
                          label: const Text('Session'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'GALERIE TERRAIN',
                      style: WildlifePokedexTheme.titleStyle(context).copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: WildlifePokedexTheme.neon,
                          ),
                        ),
                      )
                    else if (_observations.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: WildlifePokedexTheme.tileDecoration(),
                        child: Text(
                          'Aucune photo terrain — pars à l\'aventure !',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: WildlifePokedexTheme.text.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    else
                      ..._observations.map(_observationCard),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _observationCard(WildlifeObservation o) {
    final date =
        '${o.observedAt.day.toString().padLeft(2, '0')}/'
        '${o.observedAt.month.toString().padLeft(2, '0')}/'
        '${o.observedAt.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: WildlifePokedexTheme.tileDecoration(
        glow: WildlifePokedexTheme.accent,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (o.photoUrl != null)
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.network(o.photoUrl!, fit: BoxFit.cover),
            )
          else
            Container(
              height: 120,
              color: WildlifePokedexTheme.panel,
              alignment: Alignment.center,
              child: Icon(
                Icons.landscape,
                size: 48,
                color: WildlifePokedexTheme.text.withValues(alpha: 0.3),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.seenAtLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: WildlifePokedexTheme.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: WildlifePokedexTheme.text.withValues(alpha: 0.55),
                  ),
                ),
                if (o.note != null && o.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    o.note!,
                    style: TextStyle(
                      color: WildlifePokedexTheme.text.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
