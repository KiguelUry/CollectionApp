import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_group.dart';
import '../services/group_service.dart';
import 'group_badge.dart';
import 'location_picker_field.dart';

class AddItemOptions {
  final bool isWishlist;
  final String? locationUserId;
  final String? groupId;
  final String? locationId;
  final int quantity;

  const AddItemOptions({
    required this.isWishlist,
    this.locationUserId,
    this.groupId,
    this.locationId,
    this.quantity = 1,
  });
}

class AddItemOptionsDialog extends StatefulWidget {
  final String itemTitle;
  final Future<void> Function(AddItemOptions options) onConfirm;

  const AddItemOptionsDialog({
    super.key,
    required this.itemTitle,
    required this.onConfirm,
  });

  @override
  State<AddItemOptionsDialog> createState() => _AddItemOptionsDialogState();
}

class _AddItemOptionsDialogState extends State<AddItemOptionsDialog> {
  final _groupService = GroupService();
  bool _isWishlist = false;
  bool _shareWithGroup = false;
  String? _selectedProfileId;
  String? _selectedGroupId;
  String? _selectedLocationId;
  int _quantity = 1;
  List<Map<String, dynamic>> _profiles = [];
  List<CollectionGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id, username');
    final groups = await _groupService.fetchMyGroups();
    final userId = Supabase.instance.client.auth.currentUser!.id;
    if (mounted) {
      setState(() {
        _profiles = List<Map<String, dynamic>>.from(profiles);
        _groups = groups;
        _selectedProfileId = userId;
        if (_groups.isNotEmpty) _selectedGroupId = _groups.first.id;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ajouter ${widget.itemTitle}'),
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Wishlist'),
                      value: _isWishlist,
                      onChanged: (v) => setState(() => _isWishlist = v),
                    ),
                    if (!_isWishlist) ...[
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Possédé par un groupe (ex: Famille)'),
                        value: _shareWithGroup,
                        onChanged: (v) => setState(() => _shareWithGroup = v),
                      ),
                      if (_shareWithGroup && _groups.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedGroupId,
                          decoration: const InputDecoration(
                            labelText: 'Groupe',
                          ),
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
                          onChanged: (v) =>
                              setState(() => _selectedGroupId = v),
                        )
                      else if (_shareWithGroup && _groups.isEmpty)
                        const Text(
                          'Crée un groupe dans le menu « Groupes »',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      const SizedBox(height: 8),
                      if (_profiles.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedProfileId,
                          decoration: const InputDecoration(
                            labelText: 'Ajouté par / membre',
                          ),
                          items: _profiles
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p['id'].toString(),
                                  child: Text(p['username'] as String),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedProfileId = v),
                        ),
                      const SizedBox(height: 12),
                      LocationPickerField(
                        selectedLocationId: _selectedLocationId,
                        groupId: _shareWithGroup ? _selectedGroupId : null,
                        onChanged: (loc) => setState(
                          () => _selectedLocationId = loc?.id,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _loading
              ? null
              : () async {
                  final options = AddItemOptions(
                    isWishlist: _isWishlist,
                    locationUserId: _selectedProfileId,
                    groupId: _shareWithGroup ? _selectedGroupId : null,
                    locationId: _selectedLocationId,
                    quantity: _quantity,
                  );
                  await widget.onConfirm(options);
                },
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
