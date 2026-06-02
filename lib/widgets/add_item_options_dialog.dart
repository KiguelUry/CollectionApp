import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_group.dart';
import '../services/group_service.dart';
import 'bgg_network_image.dart';
import 'group_badge.dart';
import 'item_whereabouts_field.dart';
import 'personal_whereabouts_field.dart';

class AddItemOptions {
  final bool isWishlist;
  final String? locationUserId;
  final String? groupId;
  final String? locationId;
  final String? holderLabel;
  final int quantity;

  const AddItemOptions({
    required this.isWishlist,
    this.locationUserId,
    this.groupId,
    this.locationId,
    this.holderLabel,
    this.quantity = 1,
  });
}

class AddItemOptionsDialog extends StatefulWidget {
  final String itemTitle;
  final String? itemImageUrl;
  final bool defaultWishlist;
  final Future<void> Function(AddItemOptions options) onConfirm;

  const AddItemOptionsDialog({
    super.key,
    required this.itemTitle,
    required this.onConfirm,
    this.itemImageUrl,
    this.defaultWishlist = false,
  });

  @override
  State<AddItemOptionsDialog> createState() => _AddItemOptionsDialogState();
}

class _AddItemOptionsDialogState extends State<AddItemOptionsDialog> {
  final _groupService = GroupService();
  late bool _isWishlist;
  bool _shareWithGroup = false;
  String? _selectedGroupId;
  String? _selectedLocationId;
  String? _atMemberUserId;
  String? _customHolderName;
  bool _isLoanOnAdd = false;
  String? _loanFriendId;
  String? _loanExternalName;
  int _quantity = 1;
  List<CollectionGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _isWishlist = widget.defaultWishlist;
    if (_isWishlist) _quantity = 0;
    _atMemberUserId = Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    var groups = <CollectionGroup>[];
    try {
      groups = await _groupService.fetchMyGroups();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _groups = groups;
        if (_groups.isNotEmpty) _selectedGroupId = _groups.first.id;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter à la collection'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.itemImageUrl != null &&
                        widget.itemImageUrl!.trim().isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: BggNetworkImage(url: widget.itemImageUrl!),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      widget.itemTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (!widget.defaultWishlist)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Wishlist'),
                        value: _isWishlist,
                        onChanged: (v) => setState(() {
                          _isWishlist = v;
                          _quantity = v ? 0 : 1;
                        }),
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.favorite_border),
                        title: const Text('Ajout à la wishlist'),
                        subtitle: Text(
                          _quantity == 0
                              ? 'Non possédé pour l\'instant'
                              : 'Quantité : $_quantity',
                        ),
                      ),
                    if (!_isWishlist) ...[
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Partager avec un groupe'),
                        value: _shareWithGroup,
                        onChanged: (v) => setState(() {
                          _shareWithGroup = v;
                          _selectedLocationId = null;
                        }),
                      ),
                      if (_shareWithGroup && _groups.isNotEmpty)
                        DropdownButtonFormField<String>(
                          initialValue: _selectedGroupId,
                          decoration: const InputDecoration(
                            labelText: 'Groupe',
                          ),
                          items: _groups
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
                          onChanged: (v) => setState(() {
                            _selectedGroupId = v;
                            _selectedLocationId = null;
                          }),
                        )
                      else if (_shareWithGroup && _groups.isEmpty)
                        const Text(
                          'Crée un groupe dans le menu « Groupes »',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      const SizedBox(height: 8),
                      if (_shareWithGroup && _selectedGroupId != null)
                        ItemWhereaboutsField(
                          key: ValueKey('gm_$_selectedGroupId'),
                          groupId: _selectedGroupId!,
                          locationUserId: _atMemberUserId,
                          holderLabel: null,
                          customHolderName: _customHolderName,
                          isOnLoan: _isLoanOnAdd,
                          loanedToId: _loanFriendId,
                          loanedToName: _loanExternalName,
                          onChanged: ({
                            locationUserId,
                            holderLabel,
                            customHolderName,
                            clearHolder = false,
                            loanedToId,
                            loanedToName,
                            clearLoan = false,
                          }) => setState(() {
                            if (clearLoan) {
                              _isLoanOnAdd = false;
                              _loanFriendId = null;
                              _loanExternalName = null;
                              _atMemberUserId = locationUserId;
                              _customHolderName = customHolderName;
                            } else if (loanedToName != null ||
                                loanedToId != null) {
                              _isLoanOnAdd = true;
                              _loanFriendId = loanedToId;
                              _loanExternalName = loanedToName;
                              _atMemberUserId = null;
                              _customHolderName = null;
                            } else {
                              _isLoanOnAdd = false;
                              _atMemberUserId =
                                  clearHolder ? null : locationUserId;
                              _customHolderName = customHolderName;
                            }
                          }),
                        )
                      else
                        PersonalWhereaboutsField(
                          key: const ValueKey('pers_add'),
                          locationUserId: _atMemberUserId,
                          customHolderName: _customHolderName,
                          onChanged: ({
                            locationUserId,
                            holderLabel,
                            customHolderName,
                            clearHolder = false,
                          }) => setState(() {
                            _atMemberUserId =
                                clearHolder ? null : locationUserId;
                            _customHolderName = customHolderName;
                          }),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Quantité : '),
                          IconButton(
                            onPressed: _quantity > 1
                                ? () => setState(() => _quantity--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _quantity++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actionsOverflowButtonSpacing: 0,
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : () async {
                  final userId =
                      Supabase.instance.client.auth.currentUser!.id;
                  final options = AddItemOptions(
                    isWishlist: _isWishlist,
                    locationUserId: _isWishlist || _isLoanOnAdd
                        ? null
                        : (_shareWithGroup
                            ? _atMemberUserId
                            : (_atMemberUserId ?? userId)),
                    groupId: _shareWithGroup ? _selectedGroupId : null,
                    locationId:
                        _shareWithGroup ? _selectedLocationId : null,
                    holderLabel: _customHolderName,
                    quantity: _isWishlist ? 0 : _quantity,
                  );
                  try {
                    await widget.onConfirm(options);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Échec de l\'ajout — vérifie ta connexion',
                          ),
                        ),
                      );
                    }
                  }
                },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
