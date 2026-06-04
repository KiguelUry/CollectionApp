import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_subcategory.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../services/group_service.dart';
import '../services/loan_service.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/loan_item_dialog.dart';
import '../widgets/collection_cover_image.dart';
import '../widgets/group_badge.dart';
import '../widgets/item_whereabouts_field.dart';
import '../widgets/personal_whereabouts_field.dart';
import '../widgets/star_rating_bar.dart';
import '../widgets/assign_book_series_sheet.dart';
import '../widgets/item_tags_editor.dart';
import '../utils/boardgame_display.dart';
import '../services/bgg_service.dart';
import '../utils/copy_friend_item.dart';
import 'package:url_launcher/url_launcher.dart';

class ItemDetailScreen extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final String? friendUsername;

  const ItemDetailScreen({
    super.key,
    required this.item,
    this.readOnly = false,
    this.friendUsername,
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
  Set<String> _selectedGroupIds = {};
  Timer? _saveDebounce;

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
    _syncGroupSelectionFromItem();
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
          '*, locations(label), groups(name), '
          'location_holder:profiles!location_user_id(username), '
          'loaned_to:profiles!loaned_to_id(username), '
          'collection_item_tags(item_tags(id, label, color))',
        )
        .eq('id', _item.id)
        .single();
    if (mounted) {
      setState(() {
        _item = CollectionItem.fromJson(row);
        _syncGroupSelectionFromItem();
      });
    }
  }

  void _syncGroupSelectionFromItem() {
    _selectedGroupIds = {};
    if (_item.groupId != null) _selectedGroupIds.add(_item.groupId!);
    final extra = _item.metadata?['group_ids'];
    if (extra is List) {
      for (final id in extra) {
        if (id != null) _selectedGroupIds.add(id.toString());
      }
    }
    // Répare les anciennes lignes avec group_ids sans group_id en base.
    if (_item.groupId == null && _selectedGroupIds.isNotEmpty) {
      final first = _selectedGroupIds.first;
      _item = _item.copyWith(
        groupId: first,
        groupName: _groupNameById(first),
      );
    }
  }

  bool get _sharesWithGroup => _selectedGroupIds.isNotEmpty;

  String? get _primaryGroupId =>
      _item.groupId ?? (_selectedGroupIds.isEmpty ? null : _selectedGroupIds.first);

  String? _customHolderName() =>
      _item.metadata?['holder_label'] as String?;

  Map<String, dynamic> _metadataWithHolder(String? customName) {
    final meta = Map<String, dynamic>.from(_item.metadata ?? {});
    if (customName != null && customName.trim().isNotEmpty) {
      meta['holder_label'] = customName.trim();
    } else {
      meta.remove('holder_label');
    }
    return meta;
  }

  Map<String, dynamic> _metadataWithGroups(List<String> groupIds) {
    final meta = Map<String, dynamic>.from(_item.metadata ?? {});
    if (groupIds.length > 1) {
      meta['group_ids'] = groupIds;
    } else {
      meta.remove('group_ids');
    }
    return meta;
  }

  Map<String, dynamic> _metadataForSave(List<String> groupIds) =>
      _metadataWithGroups(groupIds);

  String? _groupNameById(String id) {
    for (final g in _groups) {
      if (g.id == id) return g.name;
    }
    return _item.groupName;
  }

  String _groupOwnershipSubtitle() {
    if (!_sharesWithGroup) return 'Personnel';
    final names = <String>[];
    for (final g in _groups) {
      if (_selectedGroupIds.contains(g.id)) names.add(g.name);
    }
    if (names.isEmpty) return _item.groupName ?? 'Groupe';
    return names.join(', ');
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
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final gamesPlayed = int.tryParse(_gamesPlayedController.text.trim());

    final groupIds = _selectedGroupIds.toList();
    _item = _item.copyWith(
      rating: _item.rating,
      review: _reviewController.text,
      purchasePrice: price,
      condition: _condition?.dbValue,
      gamesPlayed: gamesPlayed,
      personalRules: _personalRulesController.text,
      quantity: _item.quantity,
      locationId: _item.locationId,
      locationUserId: _item.locationUserId,
      groupId: groupIds.isEmpty ? null : groupIds.first,
      groupName: groupIds.isEmpty ? null : _groupNameById(groupIds.first),
      metadata: _metadataForSave(groupIds),
      isWishlist: _item.isWishlist,
      clearPurchasePrice: _priceController.text.trim().isEmpty,
      clearGamesPlayed: _gamesPlayedController.text.trim().isEmpty,
      clearGroup: groupIds.isEmpty,
    );

    try {
      await Supabase.instance.client
          .from('collection_items')
          .update(_item.toUpdateJson())
          .eq('id', _item.id);
      await _reloadItem();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la sauvegarde : $e')),
        );
      }
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
    final isBook = _item.category == CollectionCategory.book;
    final ro = widget.readOnly;
    final isWishlist = _item.isWishlist;
    final ownedQty = isWishlist ? 0 : _item.quantity;

    return Scaffold(
      appBar: AppAppBar(
        title: _item.title,
        showBackButton: true,
        actions: [
          if (ro && widget.friendUsername != null)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Ajouter chez moi',
              onPressed: () => showCopyFriendItemSheet(
                context,
                source: _item,
                friendUsername: widget.friendUsername!,
              ),
            ),
          if (!ro && isBook && _item.volumeId == null)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: 'Rattacher à une série',
              onPressed: () async {
                final sub = BookSubcategory.fromDbValue(_item.subcategory);
                final ok = await showAssignBookToSeriesSheet(
                  context,
                  item: _item,
                  subcategory: sub,
                );
                if (ok == true) _reloadItem();
              },
            ),
          if (!ro)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _item.imageUrl != null
                      ? SizedBox.expand(
                          child: CollectionCoverImage(
                            url: _item.imageUrl!,
                            height: 280,
                            bookCover: isBook,
                            largeSource: true,
                            fit: isBook ? BoxFit.contain : BoxFit.cover,
                          ),
                        )
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
                    if (!isBoardgame && !isWishlist) ...[
                      const SizedBox(height: 12),
                      _buildSectionTitle('Tags'),
                      ItemTagsEditor(
                        itemId: _item.id,
                        initialTags: _item.tags,
                        readOnly: ro,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildInformationsSection(
                      isBoardgame: isBoardgame,
                      metadataRows: metadataRows,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2),
                      title: Text(
                        isWishlist
                            ? 'Possédé : $ownedQty (wishlist)'
                            : 'Possédé : $ownedQty',
                      ),
                      subtitle: isWishlist
                          ? const Text(
                              'Passe à 1 pour l\'ajouter à ta collection',
                            )
                          : Text(_groupOwnershipSubtitle()),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: !ro &&
                                    !isWishlist &&
                                    _item.quantity > 1
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
                                      if (isWishlist) {
                                        _item = _item.copyWith(
                                          isWishlist: false,
                                          quantity: 1,
                                        );
                                      } else {
                                        _item = _item.copyWith(
                                          quantity: _item.quantity + 1,
                                        );
                                      }
                                    });
                                    _saveNow();
                                  }
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                    if (!isWishlist)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Partagé avec un groupe'),
                        value: _sharesWithGroup,
                        onChanged: ro
                            ? null
                            : (v) async {
                                if (v && _groups.isEmpty) {
                                  await _loadGroups();
                                }
                                if (!mounted) return;
                                if (v && _groups.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Crée d\'abord un groupe dans le menu « Groupes »',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                setState(() {
                                  if (!v) {
                                    _selectedGroupIds = {};
                                    _item = _item.copyWith(clearGroup: true);
                                  } else {
                                    final g = _groups.first;
                                    _selectedGroupIds = {g.id};
                                    _item = _item.copyWith(
                                      groupId: g.id,
                                      groupName: g.name,
                                      clearLocation: true,
                                      metadata: _metadataWithGroups(
                                        _selectedGroupIds.toList(),
                                      ),
                                    );
                                  }
                                });
                                _saveNow();
                              },
                      ),
                    if (!isWishlist && _sharesWithGroup && _groups.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Groupes',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_groups.any((g) => !_selectedGroupIds.contains(g.id)))
                        DropdownButtonFormField<String>(
                          initialValue: null,
                          decoration: const InputDecoration(
                            labelText: 'Ajouter à un groupe',
                          ),
                          items: _groups
                              .where((g) => !_selectedGroupIds.contains(g.id))
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g.id,
                                  child: GroupBadge.dropdownLabel(
                                    name: g.name,
                                    avatarUrl: g.avatarUrl,
                                    accentColor: g.accentColor,
                                    iconKey: g.iconKey,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: ro
                              ? null
                              : (id) {
                                  if (id == null) return;
                                  final g =
                                      _groups.firstWhere((x) => x.id == id);
                                  setState(() {
                                    _selectedGroupIds.add(id);
                                    _item = _item.copyWith(
                                      groupId: _selectedGroupIds.first,
                                      groupName: g.name,
                                      metadata: _metadataWithGroups(
                                        _selectedGroupIds.toList(),
                                      ),
                                      clearLocation: true,
                                    );
                                  });
                                  _saveNow();
                                },
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _groups
                            .where((g) => _selectedGroupIds.contains(g.id))
                            .map((g) {
                          return InputChip(
                            label: Text(g.name),
                            onDeleted: ro
                                ? null
                                : () {
                                    setState(() {
                                      _selectedGroupIds.remove(g.id);
                                      final ids =
                                          _selectedGroupIds.toList();
                                      if (ids.isEmpty) {
                                        _item =
                                            _item.copyWith(clearGroup: true);
                                      } else {
                                        final first = _groups
                                            .firstWhere((x) => x.id == ids.first);
                                        _item = _item.copyWith(
                                          groupId: ids.first,
                                          groupName: first.name,
                                          metadata:
                                              _metadataWithGroups(ids),
                                        );
                                      }
                                    });
                                    _saveNow();
                                  },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    IgnorePointer(
                      ignoring: ro,
                      child: isWishlist
                          ? const SizedBox.shrink()
                          : _primaryGroupId != null
                          ? ItemWhereaboutsField(
                              key: ValueKey('where_$_primaryGroupId'),
                              groupId: _primaryGroupId!,
                              locationUserId: _item.locationUserId,
                              holderLabel: _item.locationLabel,
                              customHolderName: _customHolderName(),
                              isOnLoan: _item.isOnLoan,
                              loanedToId: _item.loanedToId,
                              loanedToName: _item.loanedToName,
                              readOnly: ro,
                              onChanged: ({
                                locationUserId,
                                holderLabel,
                                customHolderName,
                                clearHolder = false,
                                loanedToId,
                                loanedToName,
                                clearLoan = false,
                              }) {
                                setState(() {
                                  if (clearLoan) {
                                    _item = _item.copyWith(
                                      clearLoan: true,
                                      metadata: _metadataWithHolder(
                                        customHolderName,
                                      ),
                                      locationUserId: locationUserId,
                                      locationLabel: holderLabel,
                                      clearLocation: clearHolder,
                                    );
                                  } else if (loanedToName != null ||
                                      loanedToId != null) {
                                    _item = _item.copyWith(
                                      clearLocation: true,
                                      clearLoan: false,
                                      loanedToId: loanedToId,
                                      loanedToName: loanedToName,
                                      loanedAt: DateTime.now(),
                                      metadata: _metadataWithHolder(null),
                                    );
                                  } else {
                                    _item = _item.copyWith(
                                      clearLoan: true,
                                      locationUserId: locationUserId,
                                      locationLabel: holderLabel,
                                      clearLocation: clearHolder,
                                      metadata: _metadataWithHolder(
                                        customHolderName,
                                      ),
                                    );
                                  }
                                });
                                _saveNow();
                              },
                            )
                          : PersonalWhereaboutsField(
                              key: const ValueKey('pers_where'),
                              locationUserId: _item.locationUserId ??
                                  Supabase.instance.client.auth.currentUser?.id,
                              customHolderName: _customHolderName(),
                              readOnly: ro,
                              onChanged: ({
                                locationUserId,
                                holderLabel,
                                customHolderName,
                                clearHolder = false,
                              }) {
                                setState(() {
                                  _item = _item.copyWith(
                                    locationUserId: locationUserId,
                                    locationLabel: holderLabel,
                                    clearLocation: clearHolder,
                                    metadata: _metadataWithHolder(
                                      customHolderName,
                                    ),
                                  );
                                });
                                _saveNow();
                              },
                            ),
                    ),
                    if (isBook && !_item.isWishlist && !_item.isSold) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lu'),
                        value: _item.isRead,
                        onChanged: ro
                            ? null
                            : (v) {
                                setState(() => _item = _item.copyWith(isRead: v));
                                _saveNow();
                              },
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
                    if (!ro && !_item.isGroupOwned) ...[
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
                    if (!ro && !isWishlist) ...[
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
                    if (isWishlist && isBoardgame) ...[
                      const Divider(height: 32),
                      _buildSectionTitle('Prix marché (indicatif)'),
                      Text(
                        'Les estimations neuf / occasion via une API ne sont pas encore disponibles. Consulte BoardGameGeek pour une fourchette.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (!isWishlist) ...[
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
                    ],
                    if (isBoardgame && !isWishlist) ...[
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

  Widget _buildInformationsSection({
    required bool isBoardgame,
    required List<MapEntry<String, String>> metadataRows,
  }) {
    final players = formatPlayerCount(_item.minPlayers, _item.maxPlayers);
    final time = formatPlayingTime(_item.playingTime);
    final bggId = _item.metadata?['bgg_id']?.toString();
    final rulesUrl = BggService.rulesFilesUrl(bggId);

    if (!isBoardgame && metadataRows.isEmpty) {
      return const SizedBox.shrink();
    }
    if (isBoardgame &&
        players == null &&
        time == null &&
        metadataRows.isEmpty &&
        rulesUrl == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Informations'),
        if (isBoardgame) ...[
          if (players != null || time != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (players != null) _infoTile(Icons.people, players),
                if (time != null) _infoTile(Icons.timer, time),
              ],
            ),
          if (metadataRows.isNotEmpty) const SizedBox(height: 8),
        ],
        ...metadataRows.map(
          (row) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              row.key,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            subtitle: Text(
              row.value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ),
        if (rulesUrl != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(rulesUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Livrets & fichiers sur BGG'),
          ),
          Text(
            'BGG ne fournit pas le PDF dans l\'app : ouverture de la page communautaire.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ],
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
