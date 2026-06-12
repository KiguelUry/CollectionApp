import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bgg_expansion.dart';
import '../models/collection_item.dart';
import '../services/bgg_service.dart';
import '../utils/boardgame_expansions.dart';
import 'bgg_network_image.dart';

/// Extensions BGG visibles uniquement sur la fiche du jeu de base.
class BoardgameExpansionsSection extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<CollectionItem> onItemUpdated;

  const BoardgameExpansionsSection({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onItemUpdated,
  });

  @override
  State<BoardgameExpansionsSection> createState() =>
      _BoardgameExpansionsSectionState();
}

class _BoardgameExpansionsSectionState extends State<BoardgameExpansionsSection> {
  List<BggExpansion>? _expansions;
  bool _loading = true;
  String? _error;
  late Set<String> _owned;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _owned = ownedExpansionBggIds(widget.item.metadata).toSet();
    _load();
  }

  @override
  void didUpdateWidget(BoardgameExpansionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _owned = ownedExpansionBggIds(widget.item.metadata).toSet();
      _showAll = false;
      _load();
    }
  }

  Future<void> _load() async {
    final bggId = widget.item.metadata?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) {
      setState(() {
        _loading = false;
        _expansions = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await BggService.fetchExpansions(bggId);
      if (!mounted) return;
      setState(() {
        _expansions = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleOwned(BggExpansion exp, bool owned) async {
    if (widget.readOnly) return;

    final next = Set<String>.from(_owned);
    if (owned) {
      next.add(exp.bggId);
    } else {
      next.remove(exp.bggId);
    }

    setState(() => _owned = next);

    final meta = metadataWithOwnedExpansions(widget.item.metadata, next.toList());
    try {
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': meta})
          .eq('id', widget.item.id);
      if (!mounted) return;
      widget.onItemUpdated(widget.item.copyWith(metadata: meta));
    } catch (e) {
      if (!mounted) return;
      setState(() => _owned = ownedExpansionBggIds(widget.item.metadata).toSet());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(
        'Extensions : $_error',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      );
    }

    final bggId = widget.item.metadata?['bgg_id']?.toString();
    if (bggId == null || bggId.isEmpty) {
      return _sectionHeader(
        'Extensions',
        subtitle: 'Ajoute ce jeu via la recherche BGG pour afficher ses extensions.',
      );
    }

    final expansions = _expansions;
    if (expansions == null || expansions.isEmpty) {
      return _sectionHeader(
        'Extensions',
        subtitle: 'Aucune extension listée sur BGG pour ce jeu.',
      );
    }

    final accent = Colors.orange.shade800;
    final ownedList =
        expansions.where((e) => _owned.contains(e.bggId)).toList();
    final otherList =
        expansions.where((e) => !_owned.contains(e.bggId)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Extensions',
          subtitle: ownedList.isEmpty
              ? '${expansions.length} sur BGG — coche celles que tu possèdes.'
              : '${ownedList.length} possédée${ownedList.length > 1 ? 's' : ''} · '
                  '${otherList.length} autre${otherList.length > 1 ? 's' : ''}',
        ),
        if (ownedList.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final exp in ownedList) ...[
            _ExpansionRow(
              expansion: exp,
              owned: true,
              readOnly: widget.readOnly,
              accent: accent,
              onToggle: (v) => _toggleOwned(exp, v),
            ),
            const SizedBox(height: 6),
          ],
        ],
        if (otherList.isNotEmpty) ...[
          const SizedBox(height: 4),
          Material(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => setState(() => _showAll = !_showAll),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _showAll ? Icons.expand_less : Icons.expand_more,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showAll
                            ? 'Masquer les autres extensions'
                            : 'Voir les ${otherList.length} autres extensions',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showAll) ...[
            const SizedBox(height: 8),
            for (final exp in otherList) ...[
              _ExpansionRow(
                expansion: exp,
                owned: false,
                readOnly: widget.readOnly,
                accent: accent,
                onToggle: (v) => _toggleOwned(exp, v),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ],
    );
  }
}

class _ExpansionRow extends StatelessWidget {
  final BggExpansion expansion;
  final bool owned;
  final bool readOnly;
  final Color accent;
  final ValueChanged<bool> onToggle;

  const _ExpansionRow({
    required this.expansion,
    required this.owned,
    required this.readOnly,
    required this.accent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: owned ? Colors.green.shade50 : Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: owned
              ? Colors.green.shade200
              : accent.withValues(alpha: 0.16),
        ),
      ),
      child: InkWell(
        onTap: readOnly ? null : () => onToggle(!owned),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: expansion.imageUrl != null
                      ? BggNetworkImage(
                          url: expansion.imageUrl!,
                          boxedCover: true,
                          largeSource: true,
                        )
                      : ColoredBox(
                          color: accent.withValues(alpha: 0.12),
                          child: Icon(Icons.extension, color: accent, size: 22),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  expansion.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (!readOnly)
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: owned,
                  activeColor: Colors.green.shade700,
                  onChanged: (v) => onToggle(v ?? false),
                )
              else if (owned)
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
