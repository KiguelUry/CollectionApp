import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../services/collection_change_history_service.dart';
import '../services/collection_refresh.dart';
import '../services/item_group_service.dart';
import '../utils/boardgame_display.dart';
import '../utils/item_copy_units.dart';
import '../utils/whereabouts_apply.dart';
import '../utils/whereabouts_persistence.dart';
import '../utils/wishlist_market_metadata.dart';
import 'bgg_community_rating_panel.dart';
import 'compact_whereabouts_dropdown.dart';
import 'item_condition_pill.dart';
import 'item_copy_units_panel.dart';
import 'households_sheet.dart';
import 'item_market_value_panel.dart';
import 'favorite_heart_button.dart';
import 'precision_star_rating_bar.dart';
import 'temporary_loan_toggle.dart';

Future<void> showBoardgameTileRatingSheet(
  BuildContext context, {
  required CollectionItem item,
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BoardgameTileRatingSheet(
      item: item,
      readOnly: readOnly,
    ),
  );
}

Future<void> showBoardgameTileLocationSheet(
  BuildContext context, {
  required CollectionItem item,
  required List<CollectionGroup> groups,
  bool readOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BoardgameTileLocationSheet(
      item: item,
      groups: groups,
      readOnly: readOnly,
    ),
  );
}

Set<String> _groupIdsFromItem(CollectionItem item) {
  final ids = <String>{};
  if (item.groupId != null) ids.add(item.groupId!);
  final extra = item.metadata?['group_ids'];
  if (extra is List) {
    for (final id in extra) {
      final s = id?.toString();
      if (s != null && s.isNotEmpty) ids.add(s);
    }
  }
  return ids;
}

class _BoardgameTileRatingSheet extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;

  const _BoardgameTileRatingSheet({
    required this.item,
    required this.readOnly,
  });

  @override
  State<_BoardgameTileRatingSheet> createState() =>
      _BoardgameTileRatingSheetState();
}

class _BoardgameTileRatingSheetState extends State<_BoardgameTileRatingSheet> {
  late double _rating;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rating = personalRatingOnFive(
          widget.item.rating,
          metadata: widget.item.metadata,
        ) ??
        0;
  }

  Future<void> _saveRating(double value) async {
    if (widget.readOnly || _saving) return;
    final clamped = double.parse(value.clamp(0.0, 5.0).toStringAsFixed(1));
    setState(() {
      _rating = clamped;
      _saving = true;
    });
    try {
      final meta = Map<String, dynamic>.from(widget.item.metadata ?? {});
      meta['rating_scale'] = '5';
      await Supabase.instance.client.from('collection_items').update({
        'rating': clamped <= 0 ? null : clamped,
        'metadata': meta,
      }).eq('id', widget.item.id);
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.item.review?.trim();
    final bggAvg = parseBggAvgRating(widget.item.metadata?['bgg_avg_rating']);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                FavoriteHeartIconButton(
                  item: widget.item,
                  readOnly: widget.readOnly,
                ),
              ],
            ),
            const SizedBox(height: 16),
            BggCommunityRatingPanel(avgRating: bggAvg),
            const SizedBox(height: 20),
            Text(
              'Ma note',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            PrecisionStarRatingBar(
              rating: _rating,
              onChanged: _saveRating,
              readOnly: widget.readOnly,
            ),
            if (review != null && review.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Mon avis',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                review,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.85),
                ),
              ),
            ] else if (!widget.readOnly) ...[
              const SizedBox(height: 12),
              Text(
                'Pas d\'avis pour l\'instant.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

}

class _BoardgameTileLocationSheet extends StatefulWidget {
  final CollectionItem item;
  final List<CollectionGroup> groups;
  final bool readOnly;

  const _BoardgameTileLocationSheet({
    required this.item,
    required this.groups,
    required this.readOnly,
  });

  @override
  State<_BoardgameTileLocationSheet> createState() =>
      _BoardgameTileLocationSheetState();
}

class _BoardgameTileLocationSheetState
    extends State<_BoardgameTileLocationSheet> {
  final _groupService = ItemGroupService();
  late CollectionItem _item;
  late Set<String> _groupSel;
  bool _saving = false;
  bool _closing = false;
  Timer? _saveDebounce;

  String? get _meUserId => Supabase.instance.client.auth.currentUser?.id;

  bool get _multi => itemUsesCopyUnits(_item);

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _groupSel = _groupIdsFromItem(_item);
    if (!_multi) _loadGroups();
  }

  Future<void> _loadGroups() async {
    final ids = await _groupService.fetchGroupIdsForItem(_item.id);
    if (!mounted || ids.isEmpty) return;
    setState(() => _groupSel = ids.toSet());
  }

  Future<void> _toggleGroup(String groupId, bool on) async {
    if (widget.readOnly) return;
    final previous = Set<String>.from(_groupSel);
    final next = Set<String>.from(_groupSel);
    on ? next.add(groupId) : next.remove(groupId);
    setState(() {
      _groupSel = next;
      _item = _item.copyWith(
        metadata: metadataWithGroupIds(_item.metadata, next.toList()),
      );
      _saving = true;
    });
    try {
      await _groupService.syncItemGroupsWithItem(_item, next.toList());
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        setState(() => _groupSel = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistCopies() async {
    if (widget.readOnly) return;
    setState(() => _saving = true);
    try {
      final ids = _groupSel.toList();
      await _groupService.syncItemGroups(_item.id, ids);
      await Supabase.instance.client.from('collection_items').update({
        'group_id': ids.isEmpty ? null : ids.first,
        'location_user_id': _item.locationUserId,
        'metadata': _item.metadata,
      }).eq('id', _item.id);
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _applyWhereabouts({
    String? locationUserId,
    String? holderLabel,
    bool clearHolder = false,
    bool manualHolder = false,
  }) {
    setState(() {
      _item = applyWhereaboutsChange(
        _item,
        locationUserId: locationUserId,
        holderLabel: holderLabel,
        clearHolder: clearHolder,
        manualHolder: manualHolder,
      );
    });
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), _persist);
  }

  Future<void> _persist() async {
    if (widget.readOnly) return;
    setState(() => _saving = true);
    try {
      final groupIds = _groupIdsFromItem(_item).toList();
      final whereabouts = buildWhereaboutsDbFields(
        _item,
        groupIds: groupIds,
      );
      final row = await Supabase.instance.client
          .from('collection_items')
          .select('metadata')
          .eq('id', _item.id)
          .maybeSingle();
      var meta = Map<String, dynamic>.from(_item.metadata ?? {});
      if (row?['metadata'] is Map) {
        meta = Map<String, dynamic>.from(row!['metadata'] as Map);
      }
      meta = mergeMetadataPreservingHolder(
        meta,
        Map<String, dynamic>.from(whereabouts['metadata'] as Map),
      );
      meta = finalizeMetadataPayload(_item, meta);

      await Supabase.instance.client.from('collection_items').update({
        'location_user_id': whereabouts['location_user_id'],
        'metadata': meta,
        ...loanDbFields(_item),
      }).eq('id', _item.id);
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _whereLabel(CollectionItem item) {
    final label = item.locationLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    if (item.locationUserId != null && item.locationUserId == _meUserId) {
      return 'Chez moi';
    }
    return 'non renseigné';
  }

  Future<void> _confirmAndClose() async {
    if (_closing) return;
    _closing = true;
    _saveDebounce?.cancel();
    // Persiste sans 2e confirmation : le choix via ✓ / puce suffit.
    if (!widget.readOnly) {
      final before = _whereLabel(widget.item);
      await _persist();
      final after = _whereLabel(_item);
      if (before != after) {
        unawaited(
          CollectionChangeHistoryService.instance.recordLocationChange(
            item: _item,
            fromLabel: before,
            toLabel: after,
          ),
        );
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groupIds = _groupSel;
    final currentLabel = _item.locationLabel?.trim();
    final multi = _multi;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmAndClose());
      },
      child: SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Localisation et partages',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (!multi && widget.groups.isNotEmpty) ...[
                Text(
                  'Partagé avec',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in widget.groups)
                      FilterChip(
                        label: Text(g.name),
                        selected: groupIds.contains(g.id),
                        selectedColor: Colors.teal.withValues(alpha: 0.2),
                        checkmarkColor: Colors.teal.shade700,
                        onSelected: widget.readOnly || _saving
                            ? null
                            : (v) => _toggleGroup(g.id, v),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showHouseholdsSheet(context),
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Foyers & lieux liés'),
                ),
              ),
              const SizedBox(height: 4),
              if (multi)
                ItemCopyUnitsPanel(
                  item: _item,
                  groups: widget.groups,
                  selectedGroupIds: groupIds,
                  readOnly: widget.readOnly,
                  mode: ItemCopyUnitsMode.whereabouts,
                  onItemChanged: (next) {
                    setState(() {
                      _item = next;
                      _groupSel = _groupIdsFromItem(next);
                    });
                    _saveDebounce?.cancel();
                    _saveDebounce = Timer(
                      const Duration(milliseconds: 350),
                      _persistCopies,
                    );
                  },
                )
              else if (widget.readOnly)
                Text(
                  currentLabel == null || currentLabel.isEmpty
                      ? 'Non renseignée'
                      : currentLabel,
                  style: const TextStyle(fontSize: 15),
                )
              else
                CompactWhereaboutsDropdown(
                  groups: widget.groups,
                  selectedGroupIds: groupIds,
                  locationUserId: _item.locationUserId,
                  holderLabel: _item.locationLabel,
                  readOnly: false,
                  applyDefaultIfEmpty: false,
                  onChanged: ({
                    locationUserId,
                    holderLabel,
                    clearHolder = false,
                    manualHolder = false,
                  }) {
                    _applyWhereabouts(
                      locationUserId: locationUserId,
                      holderLabel: holderLabel,
                      clearHolder: clearHolder,
                      manualHolder: manualHolder,
                    );
                    if (manualHolder || locationUserId != null) {
                      _schedulePersist();
                    }
                  },
                ),
              if (!multi &&
                  !widget.readOnly &&
                  isAwayFromHome(_item, meUserId: _meUserId)) ...[
                const SizedBox(height: 8),
                TemporaryLoanToggle(
                  isLoan: _item.isOnLoan,
                  loanedAt: _item.loanedAt,
                  borrowerName: _item.loanedToName,
                  enabled: !_saving,
                  onBorrowerChanged: (name) {
                    setState(() {
                      _item = _item.copyWith(
                        loanedToName: name.isEmpty ? null : name,
                      );
                    });
                    _schedulePersist();
                  },
                  onChanged: (isLoan, date) {
                    setState(() {
                      _item = applyTemporaryLoan(
                        _item,
                        isLoan: isLoan,
                        loanedAt: date,
                        meUserId: _meUserId,
                      );
                    });
                    _schedulePersist();
                  },
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Valeur rapide depuis la tuile : état et prix payé par exemplaire
/// (modifiables), puis estimations marché.
/// [showPurchaseBlock] = false pour la wishlist (pas encore acheté).
Future<void> showBoardgameTileValueSheet(
  BuildContext context, {
  required CollectionItem item,
  bool readOnly = false,
  bool? showPurchaseBlock,
}) {
  final purchase = showPurchaseBlock ?? !item.isWishlist;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BoardgameTileValueSheet(
      item: item,
      readOnly: readOnly,
      showPurchaseBlock: purchase,
    ),
  );
}

class _BoardgameTileValueSheet extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final bool showPurchaseBlock;

  const _BoardgameTileValueSheet({
    required this.item,
    required this.readOnly,
    required this.showPurchaseBlock,
  });

  @override
  State<_BoardgameTileValueSheet> createState() =>
      _BoardgameTileValueSheetState();
}

class _BoardgameTileValueSheetState extends State<_BoardgameTileValueSheet> {
  late CollectionItem _item;
  late List<ItemCopyUnit> _units;
  late List<TextEditingController> _priceCtrls;
  late List<TextEditingController> _sourceCtrls;
  late List<bool> _expanded;
  Timer? _saveDebounce;
  bool _saving = false;

  bool get _multi => itemUsesCopyUnits(_item);

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _units = _multi
        ? readCopyUnits(_item)
        : [
            ItemCopyUnit(
              index: 0,
              label: _item.metadata?['copy_label']?.toString(),
              purchasePrice: _item.purchasePrice,
              purchaseKind: PurchaseKind.fromDb(
                _item.metadata?[kPurchaseKindMetadataKey]?.toString(),
              ),
              purchaseSource:
                  _item.metadata?[kPurchaseSourceMetadataKey]?.toString(),
              condition: _item.itemCondition,
            ),
          ];
    _priceCtrls = [
      for (final u in _units)
        TextEditingController(text: _priceText(u.purchasePrice)),
    ];
    _sourceCtrls = [
      for (final u in _units)
        TextEditingController(text: u.purchaseSource ?? ''),
    ];
    // Multi-exemplaires : repliés par défaut ; un seul exemplaire reste ouvert.
    _expanded = List<bool>.generate(_units.length, (i) => _units.length == 1);
  }

  @override
  void dispose() {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      unawaited(_persist());
    }
    for (final c in _priceCtrls) {
      c.dispose();
    }
    for (final c in _sourceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  static String _priceText(double? v) {
    if (v == null || v <= 0) return '';
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static double? _parsePrice(String raw) {
    final cleaned = raw.replaceAll('€', '').replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    final v = double.tryParse(cleaned);
    return v == null || v <= 0 ? null : v;
  }

  void _updateUnit(int i, ItemCopyUnit next) {
    setState(() => _units[i] = next);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _persist);
  }

  Future<void> _persist() async {
    if (widget.readOnly) return;
    final first = _units.first;
    final Map<String, dynamic> patch;
    if (_multi) {
      final next = itemWithCopyUnits(_item, _units);
      _item = next;
      patch = {
        'metadata': next.metadata,
        'purchase_price': first.purchasePrice,
        'condition': first.condition?.dbValue,
      };
    } else {
      final meta = Map<String, dynamic>.from(_item.metadata ?? {});
      if (first.purchaseKind == null) {
        meta.remove(kPurchaseKindMetadataKey);
      } else {
        meta[kPurchaseKindMetadataKey] = first.purchaseKind!.dbValue;
      }
      final source = first.purchaseSource?.trim();
      if (source == null || source.isEmpty) {
        meta.remove(kPurchaseSourceMetadataKey);
      } else {
        meta[kPurchaseSourceMetadataKey] = source;
      }
      final copyLabel = first.label?.trim();
      if (copyLabel == null || copyLabel.isEmpty) {
        meta.remove('copy_label');
      } else {
        meta['copy_label'] = copyLabel;
      }
      _item = _item.copyWith(
        purchasePrice: first.purchasePrice,
        clearPurchasePrice: first.purchasePrice == null,
        condition: first.condition?.dbValue,
        metadata: meta,
      );
      patch = {
        'purchase_price': first.purchasePrice,
        'condition': first.condition?.dbValue,
        'metadata': meta,
      };
    }
    if (mounted) setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('collection_items')
          .update(patch)
          .eq('id', _item.id);
      CollectionRefresh.instance.bump();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paidTotal = _units
        .map((u) => u.purchasePrice ?? 0)
        .fold<double>(0, (a, b) => a + b);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Valeur',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (_units.length > 1 && paidTotal > 0)
                      Text(
                        'Total payé ${formatEuroChip(paidTotal, compact: false)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                if (widget.showPurchaseBlock)
                  for (var i = 0; i < _units.length; i++)
                    _copyValueRow(context, i),
                if (_saving) const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 10),
                ItemMarketValuePanel(
                  item: _item,
                  readOnly: widget.readOnly,
                  onItemUpdated: (next) =>
                      _item = _item.copyWith(metadata: next.metadata),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _renameUnit(int i) async {
    final ctrl = TextEditingController(text: _unitTitle(i));
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom de l\'exemplaire'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Le mien, Celui de papa…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (next == null || next.isEmpty || !mounted) return;
    _updateUnit(i, _units[i].copyWith(label: next));
  }

  String _unitTitle(int i) {
    final custom = _units[i].label?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return _units.length > 1 ? 'Exemplaire ${i + 1}' : 'Ton exemplaire';
  }

  String _collapsedSummary(ItemCopyUnit unit) {
    final parts = <String>[
      unit.condition?.label ?? 'État ?',
      if (unit.purchasePrice != null && unit.purchasePrice! > 0)
        formatEuroChip(unit.purchasePrice, compact: false),
    ];
    return parts.join(' · ');
  }

  Widget _copyValueRow(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final unit = _units[i];
    final label = _unitTitle(i);
    final open = _expanded[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _units.length > 1
                ? () => setState(() => _expanded[i] = !open)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: Colors.teal.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      open || _units.length == 1
                          ? label
                          : '$label · ${_collapsedSummary(unit)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!widget.readOnly)
                    IconButton(
                      tooltip: 'Renommer',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _renameUnit(i),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  if (_units.length > 1)
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (open) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      PopupMenuButton<int>(
                        enabled: !widget.readOnly,
                        tooltip: 'État',
                        onSelected: (idx) => _updateUnit(
                          i,
                          idx < 0
                              ? _units[i].copyWith(clearCondition: true)
                              : _units[i].copyWith(
                                  condition: ItemCondition.values[idx],
                                ),
                        ),
                        itemBuilder: (_) => [
                          for (final c in ItemCondition.values)
                            PopupMenuItem(
                              value: c.index,
                              child: ItemConditionPill(condition: c),
                            ),
                          const PopupMenuItem(
                            value: -1,
                            child: Text('Non renseigné'),
                          ),
                        ],
                        child: ItemConditionPill(condition: unit.condition),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PopupMenuButton<int>(
                        enabled: !widget.readOnly,
                        tooltip: 'Type d\'achat',
                        onSelected: (idx) => _updateUnit(
                          i,
                          idx < 0
                              ? _units[i].copyWith(clearPurchaseKind: true)
                              : _units[i].copyWith(
                                  purchaseKind: PurchaseKind.values[idx],
                                ),
                        ),
                        itemBuilder: (_) => [
                          for (var k = 0; k < PurchaseKind.values.length; k++)
                            PopupMenuItem(
                              value: k,
                              child: Text(PurchaseKind.values[k].label),
                            ),
                          const PopupMenuItem(
                            value: -1,
                            child: Text('Non renseigné'),
                          ),
                        ],
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            unit.purchaseKind?.label ?? 'Type d\'achat',
                          ),
                        ),
                      ),
                      const Text(
                        'Payé :',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _priceCtrls[i],
                          enabled: !widget.readOnly,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          decoration: const InputDecoration(
                            isDense: true,
                            suffixText: '€',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (raw) {
                            final v = _parsePrice(raw);
                            _updateUnit(
                              i,
                              v == null
                                  ? _units[i].copyWith(clearPrice: true)
                                  : _units[i].copyWith(purchasePrice: v),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Où / À qui ?',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _sourceCtrls[i],
                          enabled: !widget.readOnly,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (raw) {
                            final text = raw.trim();
                            _updateUnit(
                              i,
                              text.isEmpty
                                  ? _units[i].copyWith(clearPurchaseSource: true)
                                  : _units[i].copyWith(purchaseSource: text),
                            );
                          },
                        ),
                      ),
                      PopupMenuButton<String>(
                        enabled: !widget.readOnly,
                        tooltip: 'Suggestions',
                        onSelected: (value) {
                          _sourceCtrls[i].text = value;
                          _updateUnit(
                            i,
                            _units[i].copyWith(purchaseSource: value),
                          );
                        },
                        itemBuilder: (_) => [
                          for (final shop in purchaseSourceSuggestions)
                            PopupMenuItem(value: shop, child: Text(shop)),
                        ],
                        icon: const Icon(Icons.arrow_drop_down),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

