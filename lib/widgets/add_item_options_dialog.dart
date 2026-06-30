import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_group.dart';
import '../services/group_service.dart';
import '../utils/holder_label_utils.dart';
import '../utils/boardgame_display.dart';
import 'bgg_network_image.dart';
import 'compact_whereabouts_dropdown.dart';
import 'cover_preview_sheet.dart';
import 'group_badge.dart';

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
  final double? bggAvgRating;
  final Future<void> Function(AddItemOptions options) onConfirm;

  const AddItemOptionsDialog({
    super.key,
    required this.itemTitle,
    required this.onConfirm,
    this.itemImageUrl,
    this.defaultWishlist = false,
    this.bggAvgRating,
  });

  @override
  State<AddItemOptionsDialog> createState() => _AddItemOptionsDialogState();
}

class _AddItemOptionsDialogState extends State<AddItemOptionsDialog> {
  final _groupService = GroupService();
  late bool _isWishlist;
  bool _shareWithGroup = false;
  String? _selectedGroupId;
  String? _locationUserId;
  String? _holderLabel;
  int _quantity = 1;
  List<CollectionGroup> _groups = [];
  Map<String, int> _groupActivityCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _isWishlist = widget.defaultWishlist;
    _quantity = widget.defaultWishlist ? 0 : 1;
    _locationUserId = Supabase.instance.client.auth.currentUser?.id;
    _load();
  }

  List<CollectionGroup> get _sortedGroups {
    final copy = List<CollectionGroup>.from(_groups);
    copy.sort((a, b) {
      final ca = _groupActivityCounts[a.id] ?? 0;
      final cb = _groupActivityCounts[b.id] ?? 0;
      if (ca != cb) return cb.compareTo(ca);
      return a.name.compareTo(b.name);
    });
    return copy;
  }

  Future<void> _load() async {
    var groups = <CollectionGroup>[];
    var activity = <String, int>{};
    try {
      final results = await Future.wait([
        _groupService.fetchMyGroups(),
        _groupService.fetchGroupActivityCounts(),
      ]);
      groups = results[0] as List<CollectionGroup>;
      activity = results[1] as Map<String, int>;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _groups = groups;
        _groupActivityCounts = activity;
        _loading = false;
      });
    }
  }

  void _onWhereaboutsChanged({
    String? locationUserId,
    String? holderLabel,
    bool clearHolder = false,
    bool manualHolder = false,
  }) {
    setState(() {
      if (manualHolder) {
        _locationUserId = null;
        _holderLabel = holderLabel;
      } else if (clearHolder) {
        _locationUserId = null;
        _holderLabel = null;
      } else {
        _locationUserId = locationUserId;
        _holderLabel = holderLabel;
      }
    });
  }

  String? _holderLabelForSave() {
    if (_locationUserId != null) return null;
    final label = _holderLabel?.trim();
    if (label == null || label.isEmpty) return null;
    return holderLabelStorageValue(formatManualHolderLabel(label));
  }

  bool get _hasManualHolder =>
      _holderLabel != null && _holderLabel!.trim().isNotEmpty;

  String? _resolvedLocationUserId(String userId) {
    if (_isWishlist || _hasManualHolder) return null;
    if (_shareWithGroup) return _locationUserId;
    return _locationUserId ?? userId;
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
                      Center(
                        child: GestureDetector(
                          onTap: () => showCoverPreview(
                            context,
                            imageUrl: widget.itemImageUrl,
                            title: widget.itemTitle,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 160,
                              height: 160,
                              child: BggNetworkImage(
                                url: widget.itemImageUrl!,
                                boxedCover: true,
                                largeSource: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      widget.itemTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (widget.bggAvgRating != null) ...[
                      const SizedBox(height: 6),
                      _BggRatingPreview(avgRating: widget.bggAvgRating!),
                    ],
                    const SizedBox(height: 8),
                    if (!widget.defaultWishlist)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Wishlist'),
                        value: _isWishlist,
                        onChanged: (v) => setState(() {
                          _isWishlist = v;
                          if (v) {
                            _quantity = 0;
                          } else if (_quantity == 0) {
                            _quantity = 1;
                          }
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
                          if (!v) _selectedGroupId = null;
                        }),
                      ),
                      if (_shareWithGroup && _groups.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedGroupId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Groupe',
                          ),
                          hint: const Text('Choisir un groupe'),
                          items: _sortedGroups
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
                          onChanged: (v) => setState(() => _selectedGroupId = v),
                        )
                      else if (_shareWithGroup && _groups.isEmpty)
                        const Text(
                          'Crée un groupe dans le menu « Groupes »',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      const SizedBox(height: 8),
                      if (_shareWithGroup && _selectedGroupId != null)
                        CompactWhereaboutsDropdown(
                          key: ValueKey('gm_$_selectedGroupId'),
                          groups: _groups,
                          selectedGroupIds: {_selectedGroupId!},
                          locationUserId: _locationUserId,
                          holderLabel: _holderLabel,
                          readOnly: false,
                          applyDefaultIfEmpty: true,
                          onChanged: _onWhereaboutsChanged,
                        )
                      else if (!_shareWithGroup)
                        CompactWhereaboutsDropdown(
                          key: const ValueKey('pers_add'),
                          groups: const [],
                          selectedGroupIds: const {},
                          locationUserId: _locationUserId,
                          holderLabel: _holderLabel,
                          readOnly: false,
                          applyDefaultIfEmpty: true,
                          onChanged: _onWhereaboutsChanged,
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
                  if (_shareWithGroup &&
                      !_isWishlist &&
                      _selectedGroupId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Choisis un groupe pour le partage'),
                      ),
                    );
                    return;
                  }
                  final userId =
                      Supabase.instance.client.auth.currentUser!.id;
                  final options = AddItemOptions(
                    isWishlist: _isWishlist,
                    locationUserId: _resolvedLocationUserId(userId),
                    groupId: _shareWithGroup ? _selectedGroupId : null,
                    holderLabel: _holderLabelForSave(),
                    quantity: _quantity,
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

class _BggRatingPreview extends StatelessWidget {
  final double avgRating;

  const _BggRatingPreview({required this.avgRating});

  @override
  Widget build(BuildContext context) {
    final onFive = bggRatingOnFive(avgRating);
    if (onFive == null) return const SizedBox.shrink();
    final chipLabel = formatBggRatingChipLabel(avgRating) ?? onFive.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.shade700.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade700),
          const SizedBox(width: 6),
          Text(
            'Note communautaire : $chipLabel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
