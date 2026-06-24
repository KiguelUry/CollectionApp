import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_category.dart';
import '../../services/nominatim_service.dart';
import '../../services/profile_service.dart';

class RestaurantSearchScreen extends StatefulWidget {
  const RestaurantSearchScreen({super.key});

  @override
  State<RestaurantSearchScreen> createState() => _RestaurantSearchScreenState();
}

class _RestaurantSearchScreenState extends State<RestaurantSearchScreen> {
  final _query = TextEditingController();
  List<NominatimPlace> _places = [];
  bool _loading = false;
  bool _asWishlist = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    final hits = await NominatimService.searchPlaces(_query.text);
    if (mounted) {
      setState(() {
        _places = hits;
        _loading = false;
      });
    }
  }

  Future<void> _add(NominatimPlace place) async {
    try {
      await ProfileService().ensureCurrentUserProfile();
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final name = place.displayName.split(',').first.trim();
      await Supabase.instance.client.from('collection_items').insert({
        'title': name,
        'category': CollectionCategory.restaurant.dbValue,
        'is_wishlist': _asWishlist,
        'metadata': {
          ...place.toRestaurantMetadata(),
          'source': 'nominatim',
        },
        'added_by': userId,
        'location_user_id': userId,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('« $name » ajouté')),
        );
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Chercher un restaurant')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    hintText: 'Nom + ville (OpenStreetMap)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ajouter à la wishlist'),
                  value: _asWishlist,
                  onChanged: (v) => setState(() => _asWishlist = v),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _places.length,
              itemBuilder: (context, i) {
                final p = _places[i];
                return ListTile(
                  leading: const Icon(Icons.restaurant),
                  title: Text(p.displayName.split(',').first),
                  subtitle: Text(
                    p.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _add(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
