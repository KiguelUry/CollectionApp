import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_item.dart';
import '../../models/wildlife_observation.dart';
import '../../services/wildlife_service.dart';
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
          title: const Text('Nouvelle observation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: placeController,
                  decoration: const InputDecoration(
                    labelText: 'Lieu',
                    hintText: 'Parc national, jardin…',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'Vu ici, pris en photo là…',
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
              child: const Text('Enregistrer'),
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
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final path =
            '${Supabase.instance.client.auth.currentUser!.id}/wildlife/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        photoUrl =
            Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      }
    } catch (_) {}

    await _service.addObservation(
      itemId: widget.item.id,
      observedAt: DateTime.now(),
      note: noteController.text,
      placeLabel: placeController.text,
      latitude: lat,
      longitude: lng,
      photoUrl: photoUrl,
    );

    final count = _observations.length + 1;
    await Supabase.instance.client.from('collection_items').update({
      'games_played': count,
    }).eq('id', widget.item.id);

    _load();
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.item.metadata ?? {};
    final desc = meta['description'] as String?;
    final scientific = meta['scientific_name'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.item.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CollectionCoverImage(
                url: widget.item.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 12),
          if (scientific != null)
            Text(
              scientific,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700,
              ),
            ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc),
          ],
          const Divider(height: 32),
          Row(
            children: [
              Text(
                'Observations',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addObservation,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Session'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_observations.isEmpty)
            Text(
              'Aucune observation pour l\'instant.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          else
            ..._observations.map(
              (o) => Card(
                child: ListTile(
                  leading: o.photoUrl != null
                      ? Image.network(o.photoUrl!, width: 48, height: 48,
                          fit: BoxFit.cover)
                      : const Icon(Icons.place_outlined),
                  title: Text(o.placeLabel ?? 'Observation'),
                  subtitle: Text(
                    [
                      '${o.observedAt.day}/${o.observedAt.month}/${o.observedAt.year}',
                      if (o.note != null) o.note!,
                    ].join(' · '),
                    maxLines: 3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
