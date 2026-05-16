import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/star_rating_bar.dart';

class ItemDetailScreen extends StatefulWidget {
  final CollectionItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late CollectionItem _item;
  late final TextEditingController _reviewController;
  late final TextEditingController _priceController;
  late final TextEditingController _gamesPlayedController;
  late final TextEditingController _personalRulesController;

  ItemCondition? _condition;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _condition = _item.itemCondition;
    _reviewController = TextEditingController(text: _item.review ?? '');
    _priceController = TextEditingController(
      text: _item.purchasePrice?.toString() ?? '',
    );
    _gamesPlayedController = TextEditingController(
      text: _item.gamesPlayed?.toString() ?? '',
    );
    _personalRulesController = TextEditingController(
      text: _item.personalRules ?? '',
    );
  }

  @override
  void dispose() {
    _reviewController.dispose();
    _priceController.dispose();
    _gamesPlayedController.dispose();
    _personalRulesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final gamesPlayed = int.tryParse(_gamesPlayedController.text.trim());

    _item = _item.copyWith(
      rating: _item.rating,
      review: _reviewController.text,
      purchasePrice: price,
      condition: _condition?.dbValue,
      gamesPlayed: gamesPlayed,
      personalRules: _personalRulesController.text,
      clearPurchasePrice: _priceController.text.trim().isEmpty,
      clearGamesPlayed: _gamesPlayedController.text.trim().isEmpty,
    );

    try {
      await Supabase.instance.client
          .from('collection_items')
          .update(_item.toUpdateJson())
          .eq('id', _item.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enregistré')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadataRows = CategoryMetadata.detailRows(_item);
    final isBoardgame = _item.category == CollectionCategory.boardgame;

    return Scaffold(
      floatingActionButton: _saving
          ? const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(color: Colors.white),
            )
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _item.imageUrl != null
                      ? BggNetworkImage(url: _item.imageUrl!)
                      : Container(color: _item.category.color),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(_item.category.icon, size: 18),
                          label: Text(_item.category.label),
                        ),
                        if (_item.bookSubcategory != null)
                          Chip(label: Text(_item.bookSubcategory!.label)),
                        if (_item.cardSubcategory != null)
                          Chip(label: Text(_item.cardSubcategory!.label)),
                      ],
                    ),
                    if (isBoardgame) ...[
                      const SizedBox(height: 16),
                      _buildSectionTitle('Informations BGG'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _infoTile(
                            Icons.people,
                            '${_item.minPlayers ?? '?'}-${_item.maxPlayers ?? '?'}',
                          ),
                          _infoTile(
                            Icons.timer,
                            _item.playingTime != null
                                ? '${_item.playingTime} min'
                                : '?',
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                    ],
                    if (metadataRows.isNotEmpty) ...[
                      _buildSectionTitle('Détails'),
                      ...metadataRows.map(
                        (row) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            row.key,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            row.value,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                    ],
                    _buildSectionTitle('Ma note & avis'),
                    const Text(
                      'Note',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    StarRatingBar(
                      rating: _item.rating ?? 0,
                      onChanged: (value) {
                        setState(() {
                          _item = _item.copyWith(
                            rating: value <= 0 ? null : value,
                            clearRating: value <= 0,
                          );
                        });
                      },
                    ),
                    if (_item.rating != null)
                      Text(
                        '${_item.rating!.toStringAsFixed(1)} / 5',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reviewController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Mon avis',
                        hintText: 'Ce que j\'en pense, pour la famille…',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const Divider(height: 32),
                    _buildSectionTitle('Valeur & état'),
                    TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Prix d\'achat (€)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.euro),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ItemCondition?>(
                      value: _condition,
                      decoration: const InputDecoration(
                        labelText: 'État',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<ItemCondition?>(
                          value: null,
                          child: Text('— Non renseigné —'),
                        ),
                        ...ItemCondition.values.map(
                          (c) => DropdownMenuItem<ItemCondition?>(
                            value: c,
                            child: Text(c.label),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _condition = val),
                    ),
                    if (isBoardgame) ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Ma collection — Jeu de société'),
                      TextField(
                        controller: _gamesPlayedController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de parties jouées',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.repeat),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _personalRulesController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Règles personnalisées',
                          hintText:
                              'Variantes maison, rappels, extensions utilisées…',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ] else ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Notes personnelles'),
                      TextField(
                        controller: _personalRulesController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 30),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
