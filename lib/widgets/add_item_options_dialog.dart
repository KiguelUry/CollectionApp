import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_group.dart';
import '../services/bgg_service.dart';
import '../services/group_service.dart';
import '../utils/bgg_text.dart';
import '../utils/crowdfunding_search.dart';
import '../utils/display_text.dart';
import '../utils/holder_label_utils.dart';
import '../utils/boardgame_display.dart';
import 'bgg_network_image.dart';
import 'bgg_photo_strip.dart';
import 'collection_cover_image.dart';
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

/// Modale unifiée d'aperçu + options d'ajout (Découvrir / Collection / Wishlist).
class AddItemOptionsDialog extends StatefulWidget {
  final String itemTitle;
  final String? itemImageUrl;
  /// Couverture verticale livre (2:3) au lieu du carré jeux.
  final bool bookCover;
  final bool defaultWishlist;
  final double? bggAvgRating;
  final int? yearPublished;
  final int? minPlayers;
  final int? maxPlayers;
  final int? playingTime;
  final String? description;
  final String? bggId;
  final List<BggGalleryPhoto>? photos;
  /// Affiche « Chercher le projet » (Kickstarter / Gamefound) pour les sorties.
  final bool showCrowdfundingSearch;
  final Future<void> Function(AddItemOptions options) onConfirm;

  const AddItemOptionsDialog({
    super.key,
    required this.itemTitle,
    required this.onConfirm,
    this.itemImageUrl,
    this.bookCover = false,
    this.defaultWishlist = false,
    this.bggAvgRating,
    this.yearPublished,
    this.minPlayers,
    this.maxPlayers,
    this.playingTime,
    this.description,
    this.bggId,
    this.photos,
    this.showCrowdfundingSearch = false,
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
  bool _descExpanded = false;
  List<BggGalleryPhoto> _photos = const [];
  bool _photosLoading = false;

  @override
  void initState() {
    super.initState();
    _isWishlist = widget.defaultWishlist;
    _quantity = widget.defaultWishlist ? 0 : 1;
    _locationUserId = Supabase.instance.client.auth.currentUser?.id;
    _photos = widget.photos ?? const [];
    _load();
    if (_photos.isEmpty && (widget.bggId ?? '').isNotEmpty) {
      unawaited(_loadPhotos());
    }
  }

  Future<void> _openCrowdfundingSearch() async {
    await launchCrowdfundingSearch(widget.itemTitle);
  }

  Future<void> _loadPhotos() async {
    final id = widget.bggId?.trim();
    if (id == null || id.isEmpty) return;
    setState(() => _photosLoading = true);
    try {
      final photos = await BggService.fetchCommunityGallery(id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _photosLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _photosLoading = false);
    }
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

  String get _metaLine {
    final parts = <String>[];
    if (widget.yearPublished != null) parts.add('${widget.yearPublished}');
    final players = formatPlayerCount(widget.minPlayers, widget.maxPlayers);
    if (players != null) parts.add(players);
    if (widget.playingTime != null && widget.playingTime! > 0) {
      parts.add('${widget.playingTime} min');
    }
    return parts.join(' · ');
  }


  String get _cleanDescription => cleanBggText(widget.description);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final desc = _cleanDescription;

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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: (widget.itemImageUrl != null &&
                                  widget.itemImageUrl!.trim().isNotEmpty)
                              ? () => showCoverPreview(
                                    context,
                                    imageUrl: widget.itemImageUrl,
                                    title: widget.itemTitle,
                                    bookCover: widget.bookCover,
                                  )
                              : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: widget.bookCover ? 72 : 96,
                              height: widget.bookCover ? 108 : 96,
                              child: (widget.itemImageUrl != null &&
                                      widget.itemImageUrl!.trim().isNotEmpty)
                                  ? (widget.bookCover
                                      ? CollectionCoverImage(
                                          url: widget.itemImageUrl!,
                                          bookCover: true,
                                          fit: BoxFit.cover,
                                        )
                                      : BggNetworkImage(
                                          url: widget.itemImageUrl!,
                                          boxedCover: true,
                                          compact: true,
                                        ))
                                  : CoverImagePlaceholder(
                                      width: widget.bookCover ? 72 : 96,
                                      height: widget.bookCover ? 108 : 96,
                                      bookCover: widget.bookCover,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cleanDisplayText(widget.itemTitle),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (widget.bggAvgRating != null) ...[
                                const SizedBox(height: 4),
                                _BggRatingPreview(
                                  avgRating: widget.bggAvgRating!,
                                ),
                              ],
                              if (_metaLine.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _metaLine,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (widget.showCrowdfundingSearch) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _openCrowdfundingSearch,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('🔍 Chercher le projet'),
                      ),
                    ],
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () =>
                            setState(() => _descExpanded = !_descExpanded),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            desc,
                            maxLines: _descExpanded ? 40 : 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.35),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _descExpanded = !_descExpanded),
                          child: Text(
                            _descExpanded ? 'Réduire' : 'Lire la suite',
                          ),
                        ),
                      ),
                    ],
                    if (_photosLoading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 2),
                    ] else if (_photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Aperçus & matériel du jeu',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      BggPhotoStrip(photos: _photos),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Wishlist'),
                      value: _isWishlist,
                      onChanged: (v) => setState(() {
                        _isWishlist = v;
                        if (v) {
                          _quantity = 0;
                          _shareWithGroup = false;
                          _selectedGroupId = null;
                        } else if (_quantity == 0) {
                          _quantity = 1;
                        }
                      }),
                    ),
                    if (_isWishlist)
                      Text(
                        'Tu pourras comparer les prix depuis la wishlist.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
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
                          initialValue: _selectedGroupId,
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
                          onChanged: (v) =>
                              setState(() => _selectedGroupId = v),
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
    final chipLabel =
        formatBggRatingChipLabel(avgRating) ?? onFive.toStringAsFixed(1);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.shade700.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: Colors.amber.shade700.withValues(alpha: 0.35)),
        ),
        child: Text(
          '★ BGG $chipLabel / 5',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.amber.shade800,
          ),
        ),
      ),
    );
  }
}
