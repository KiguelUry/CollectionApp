import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../services/collection_refresh.dart';
import '../utils/boardgame_display.dart';
import '../utils/whereabouts_apply.dart';
import '../utils/whereabouts_persistence.dart';
import 'bgg_community_rating_panel.dart';
import 'compact_whereabouts_dropdown.dart';
import 'star_rating_bar.dart';

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
    _rating = widget.item.rating ?? 0;
  }

  Future<void> _saveRating(double value) async {
    if (widget.readOnly || _saving) return;
    setState(() {
      _rating = value;
      _saving = true;
    });
    try {
      await Supabase.instance.client
          .from('collection_items')
          .update({'rating': value <= 0 ? null : value})
          .eq('id', widget.item.id);
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
            Text(
              widget.item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
            if (widget.readOnly)
              _readOnlyStars(_rating)
            else
              StarRatingBar(
                rating: _rating,
                onChanged: _saveRating,
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

  Widget _readOnlyStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating >= i + 0.5;
        return Icon(
          half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          size: 22,
          color: Colors.amber.shade700,
        );
      }),
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
  late CollectionItem _item;
  bool _saving = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
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
  Widget build(BuildContext context) {
    final groupIds = _groupIdsFromItem(_item);
    final currentLabel = _item.locationLabel?.trim();

    return SafeArea(
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
                'Localisation',
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
              if (widget.readOnly)
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
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
