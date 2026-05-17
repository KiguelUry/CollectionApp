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
import '../services/loan_service.dart';
import '../widgets/loan_item_dialog.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/group_badge.dart';
import '../widgets/location_picker_field.dart';
import '../widgets/star_rating_bar.dart';
import '../widgets/item_tags_editor.dart';

class ItemDetailScreen extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;

  const ItemDetailScreen({
    super.key,
    required this.item,
    this.readOnly = false,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _loanService = LoanService();
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
    if (!widget.readOnly) {
      _reviewController.addListener(_scheduleSave);
      _priceController.addListener(_scheduleSave);
      _gamesPlayedController.addListener(_scheduleSave);
      _personalRulesController.addListener(_scheduleSave);
      _loadGroups();
      _reloadItem();
    }
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
        .select(
          '*, locations(label), groups(name), loaned_to:profiles!loaned_to_id(username), '
          'collection_item_tags(item_tags(id, label, color))',
        )
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

  Future<void> _lend() async {
    if (_item.isWishlist || _item.isSold) return;

    final result = await showLoanItemDialog(
      context: context,
      itemTitle: _item.title,
    );
    if (result == null || !mounted) return;

    try {
      final updated = result.profileId != null
          ? await _loanService.lendToFriend(
              itemId: _item.id,
              profileId: result.profileId!,
              displayName: result.displayName!,
            )
          : await _loanService.lendToExternal(
              itemId: _item.id,
              name: result.externalName!,
            );
      if (mounted) {
        setState(() => _item = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Prêté à ${updated.loaneeDisplayName}')),
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

  Future<void> _returnLoan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objet rendu ?'),
        content: Text(
          'Confirmer que « ${_item.title} » est de retour ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marquer rendu'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final updated = await _loanService.returnItem(_item.id);
      if (mounted) {
        setState(() => _item = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prêt clôturé')),
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

  String? _loanSinceLabel() {
    final at = _item.loanedAt;
    if (at == null) return null;
    final d = at.toLocal();
    return 'Depuis le ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
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
    final ro = widget.readOnly;

    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!ro && _saveStatus != null)
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
          if (!ro)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      floatingActionButton: ro
          ? null
          : FloatingActionButton(
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
                    if (ro)
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.visibility, color: Colors.blue.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Collection d\'un ami — lecture seule',
                                  style: TextStyle(color: Colors.blue.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (ro) const SizedBox(height: 12),
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
                    if (_item.createdAtLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _item.createdAtLabel!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildSectionTitle('Tags'),
                    ItemTagsEditor(
                      itemId: _item.id,
                      initialTags: _item.tags,
                      readOnly: ro,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2),
                      title: Text('Possédé : ${_item.quantity}'),
                      subtitle: Text(_item.ownershipLabel ?? 'Personnel'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: !ro && _item.quantity > 1
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
                            onPressed: !ro
                                ? () {
                                    setState(() {
                                      _item = _item.copyWith(
                                        quantity: _item.quantity + 1,
                                      );
                                    });
                                    _saveNow();
                                  }
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Partagé avec un groupe'),
                      value: _item.isGroupOwned,
                      onChanged: ro
                          ? null
                          : (v) {
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
                        initialValue: _item.groupId,
                        decoration: const InputDecoration(labelText: 'Groupe'),
                        items: _groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Row(
                                  children: [
                                    GroupBadge.fromGroup(
                                      name: g.name,
                                      avatarUrl: g.avatarUrl,
                                      accentColor: g.accentColor,
                                      iconKey: g.iconKey,
                                      radius: 14,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(g.name)),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: ro
                            ? null
                            : (id) {
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
                    IgnorePointer(
                      ignoring: ro,
                      child: LocationPickerField(
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
                      onChanged: ro
                          ? (_) {}
                          : (value) {
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
                      readOnly: ro,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Mon avis',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (!ro) ...[
                    const Divider(height: 32),
                    _buildSectionTitle('Prêt'),
                    if (_item.isOnLoan) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.handshake,
                          color: Colors.blue.shade700,
                        ),
                        title: Text('Prêté à ${_item.loaneeDisplayName}'),
                        subtitle: Text(
                          [
                            if (_loanSinceLabel() != null) _loanSinceLabel()!,
                            if (_item.loanedToId != null) 'Ami sur l\'app',
                            if (_item.loanedToId == null) 'Hors app',
                          ].join(' · '),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _returnLoan,
                        icon: const Icon(Icons.undo),
                        label: const Text('Marquer comme rendu'),
                      ),
                    ] else if (!_item.isWishlist && !_item.isSold)
                      FilledButton.icon(
                        onPressed: _lend,
                        icon: const Icon(Icons.handshake_outlined),
                        label: const Text('Prêter cet objet'),
                      )
                    else
                      Text(
                        'Les objets en wishlist ou vendus ne peuvent pas être prêtés.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (!ro) ...[
                    const Divider(height: 32),
                    _buildSectionTitle('Doubles & vente'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('À vendre / échanger'),
                      subtitle: const Text(
                        'Apparaît dans l\'onglet « À vendre »',
                      ),
                      value: _item.isForSale && !_item.isSold,
                      onChanged: _item.isSold
                          ? null
                          : (v) {
                              setState(() {
                                _item = _item.copyWith(
                                  isForSale: v,
                                  isSold: false,
                                );
                              });
                              _saveNow();
                            },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Marquer comme vendu'),
                      subtitle: const Text(
                        'Retire de la collection active, tuile grisée dans l\'historique',
                      ),
                      value: _item.isSold,
                      onChanged: (v) {
                        setState(() {
                          _item = _item.copyWith(
                            isSold: v,
                            isForSale: v ? false : _item.isForSale,
                          );
                        });
                        _saveNow();
                      },
                    ),
                    ],
                    const Divider(height: 32),
                    _buildSectionTitle('Valeur & état'),
                    TextField(
                      controller: _priceController,
                      readOnly: ro,
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
                      initialValue: _condition,
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
                      onChanged: ro
                          ? null
                          : (val) {
                              setState(() => _condition = val);
                              _scheduleSave();
                            },
                    ),
                    if (isBoardgame) ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Jeu de société'),
                      TextField(
                        controller: _gamesPlayedController,
                        readOnly: ro,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de parties jouées',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _personalRulesController,
                        readOnly: ro,
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
                        readOnly: ro,
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
