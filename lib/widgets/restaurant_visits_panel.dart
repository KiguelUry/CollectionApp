import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/restaurant_visit.dart';
import '../services/restaurant_service.dart';
import 'star_rating_bar.dart';

/// Journal de visites pour un restaurant (date, note, plats, « fait avec »).
class RestaurantVisitsPanel extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;

  const RestaurantVisitsPanel({
    super.key,
    required this.item,
    this.readOnly = false,
  });

  @override
  State<RestaurantVisitsPanel> createState() => _RestaurantVisitsPanelState();
}

class _RestaurantVisitsPanelState extends State<RestaurantVisitsPanel> {
  final _service = RestaurantService();
  List<RestaurantVisit> _visits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _visits = await _service.fetchForItem(widget.item.id);
    if (mounted) setState(() => _loading = false);
  }

  double? get _itemLat {
    final v = widget.item.metadata?['latitude'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  double? get _itemLon {
    final v = widget.item.metadata?['longitude'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  Future<void> _addVisit() async {
    var visitedAt = DateTime.now();
    var rating = 0.0;
    final reviewController = TextEditingController();
    final friendController = TextEditingController();
    final dishesController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nouvelle visite'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(
                    '${visitedAt.day.toString().padLeft(2, '0')}/'
                    '${visitedAt.month.toString().padLeft(2, '0')}/'
                    '${visitedAt.year}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: visitedAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setLocal(() => visitedAt = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                StarRatingBar(
                  rating: rating,
                  onChanged: (v) => setLocal(() => rating = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Avis',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dishesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Plats mangés',
                    hintText: 'Un plat par ligne',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: friendController,
                  decoration: const InputDecoration(
                    labelText: 'Fait avec',
                    hintText: 'Prénom d\'un ami',
                    prefixIcon: Icon(Icons.people_outline),
                    border: OutlineInputBorder(),
                  ),
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

    final dishNames = dishesController.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final dishes = <Map<String, dynamic>>[
      for (final name in dishNames) {'name': name},
    ];

    // Photo optionnelle pour le premier plat renseigné.
    if (dishes.isNotEmpty) {
      try {
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (picked != null) {
          final bytes = await picked.readAsBytes();
          final userId = Supabase.instance.client.auth.currentUser!.id;
          final path =
              '$userId/restaurant/${DateTime.now().millisecondsSinceEpoch}.jpg';
          await Supabase.instance.client.storage.from('avatars').uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          dishes[0]['photo_url'] =
              Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
        }
      } catch (_) {}
    }

    await _service.addVisit(
      itemId: widget.item.id,
      visitedAt: visitedAt,
      rating: rating > 0 ? rating.round() : null,
      review: reviewController.text,
      dishes: dishes,
      withFriendName: friendController.text.trim().isEmpty
          ? null
          : friendController.text.trim(),
      latitude: _itemLat,
      longitude: _itemLon,
    );

    if (widget.item.isWishlist) {
      await Supabase.instance.client.from('collection_items').update({
        'is_wishlist': false,
      }).eq('id', widget.item.id);
    }

    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visite enregistrée')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Journal de visites',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (!widget.readOnly)
              TextButton.icon(
                onPressed: _addVisit,
                icon: const Icon(Icons.add),
                label: const Text('Visite'),
              ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_visits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucune visite enregistrée.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          ..._visits.map(_visitTile),
      ],
    );
  }

  Widget _visitTile(RestaurantVisit v) {
    final date =
        '${v.visitedAt.day.toString().padLeft(2, '0')}/'
        '${v.visitedAt.month.toString().padLeft(2, '0')}/'
        '${v.visitedAt.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(date, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (v.rating != null) ...[
                  const SizedBox(width: 8),
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < v.rating! ? Icons.star : Icons.star_border,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ],
              ],
            ),
            if (v.withFriendName != null && v.withFriendName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Fait avec ${v.withFriendName}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            if (v.review != null && v.review!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(v.review!),
              ),
            if (v.dishes.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Plats',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              ...v.dishes.map((d) {
                final name = d['name']?.toString() ?? '';
                final photo = d['photo_url']?.toString();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(photo, width: 40, height: 40, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.restaurant_menu, size: 20),
                  title: Text(name),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
