import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../models/storage_location.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/location_picker_field.dart';
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
  List<CollectionGroup> _groups = [];
  Timer? _saveDebounce;
  bool _saving = false;
  String? _saveStatus;

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
    _reviewController.addListener(_scheduleSave);
    _priceController.addListener(_scheduleSave);
    _gamesPlayedController.addListener(_scheduleSave);
    _personalRulesController.addListener(_scheduleSave);
    _loadGroups();
    _reloadItem();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _reviewController.dispose();
    _priceController.dispose();
    _gamesPlayedController.dispose();
    _personalRulesController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    _groups = await GroupService().fetchMyGroups();
    if (mounted) setState(() {});
  }

  Future<void> _reloadItem() async {
    final row = await Supabase.instance.client
        .from('collection_items')
        .select('*, locations(label), groups(name)')
        .eq('id', _item.id)
        .single();
    if (mounted) {
      setState(() => _item = CollectionItem.fromJson(row));
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), _save);
  }

  void _saveNow() {
    _saveDebounce?.cancel();
    _save();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveStatus = 'Enregistrement…';
    });

    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final gamesPlayed = int.tryParse(_gamesPlayedController.text.trim());

    _item = _item.copyWith(
      rating: _item.rating,
      review: _reviewController.text,
      purchasePrice: price,
      condition: _condition?.dbValue,
      gamesPlayed: gamesPlayed,
      personalRules: _personalRulesController.text,
      quantity: _item.quantity,
      locationId: _item.locationId,
      groupId: _item.groupId,
      clearPurchasePrice: _priceController.text.trim().isEmpty,
      clearGamesPlayed: _gamesPlayedController.text.trim().isEmpty,
    );

    try {
      await Supabase.instance.client
          .from('collection_items')
          .update(_item.toUpdateJson())
          .eq('id', _item.id);
      await _reloadItem();
      if (mounted) setState(() => _saveStatus = 'Enregistré');
    } catch (e) {
      if (mounted) setState(() => _saveStatus = 'Erreur');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('« ${_item.title} » sera retiré de la collection.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await Supabase.instance.client
        .from('collection_items')
        .delete()
        .eq('id', _item.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final metadataRows = CategoryMetadata.detailRows(_item);
    final isBoardgame = _item.category == CollectionCategory.boardgame;

    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_saveStatus != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  _saveStatus!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _saving ? Colors.white70 : Colors.white,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saving ? null : _saveNow,
        child: _saving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.save),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
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
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2),
                      title: Text('Possédé : ${_item.quantity}'),
                      subtitle: Text(_item.ownershipLabel ?? 'Personnel'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _item.quantity > 1
                                ? () {
                                    setState(() {
                                      _item = _item.copyWith(
                                        quantity: _item.quantity - 1,
                                      );
                                    });
                                    _saveNow();
                                  }
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _item = _item.copyWith(
                                  quantity: _item.quantity + 1,
                                );
                              });
                              _saveNow();
                            },
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Partagé avec un groupe'),
                      value: _item.isGroupOwned,
                      onChanged: (v) {
                        setState(() {
                          if (!v) {
                            _item = _item.copyWith(clearGroup: true);
                          } else if (_groups.isNotEmpty) {
                            _item = _item.copyWith(
                              groupId: _groups.first.id,
                              groupName: _groups.first.name,
                            );
                          }
                        });
                        _saveNow();
                      },
                    ),
                    if (_item.isGroupOwned && _groups.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: _item.groupId,
                        decoration: const InputDecoration(labelText: 'Groupe'),
                        items: _groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Text(g.name),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          final g = _groups.firstWhere((x) => x.id == id);
                          setState(() {
                            _item = _item.copyWith(
                              groupId: g.id,
                              groupName: g.name,
                            );
                          });
                          _saveNow();
                        },
                      ),
                    const SizedBox(height: 8),
                    LocationPickerField(
                      selectedLocationId: _item.locationId,
                      groupId: _item.groupId,
                      onChanged: (StorageLocation? loc) {
                        setState(() {
                          _item = loc == null
                              ? _item.copyWith(clearLocation: true)
                              : _item.copyWith(
                                  locationId: loc.id,
                                  locationLabel: loc.label,
                                );
                        });
                        _saveNow();
                      },
                    ),
                    if (isBoardgame) ...[
                      const Divider(height: 32),
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
                    ],
                    if (metadataRows.isNotEmpty) ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Détails'),
                      ...metadataRows.map(
                        (row) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(row.key,
                              style: TextStyle(color: Colors.grey.shade600)),
                          subtitle: Text(row.value,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    _buildSectionTitle('Ma note & avis'),
                    StarRatingBar(
                      rating: _item.rating ?? 0,
                      onChanged: (value) {
                        setState(() {
                          _item = _item.copyWith(
                            rating: value <= 0 ? null : value,
                            clearRating: value <= 0,
                          );
                        });
                        _saveNow();
                      },
                    ),
                    TextField(
                      controller: _reviewController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Mon avis',
                        border: OutlineInputBorder(),
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
                      ),
                    ),
                    const SizedBox(height: 12),
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
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.label),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _condition = val);
                        _scheduleSave();
                      },
                    ),
                    if (isBoardgame) ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Jeu de société'),
                      TextField(
                        controller: _gamesPlayedController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de parties jouées',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _personalRulesController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Règles personnalisées',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Notes'),
                      TextField(
                        controller: _personalRulesController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes personnelles',
                          border: OutlineInputBorder(),
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
