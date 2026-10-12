import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/collection_item.dart';
import '../collection_cover_image.dart';

class ShowcaseLayoutItem {
  final String itemId;
  double x;
  double y;
  double scale; // 0.55 – 1.35
  double rotation; // radians

  ShowcaseLayoutItem({
    required this.itemId,
    this.x = 0,
    this.y = 0,
    this.scale = 0.85,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': itemId,
        'x': x,
        'y': y,
        's': scale,
        'r': rotation,
      };

  factory ShowcaseLayoutItem.fromJson(Map<String, dynamic> json) {
    return ShowcaseLayoutItem(
      itemId: json['id']?.toString() ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      scale: (json['s'] as num?)?.toDouble() ?? 0.85,
      rotation: (json['r'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Vitrine libre : glisser, redimensionner, pivoter (doigt / souris).
class FavoritesShowcase extends StatefulWidget {
  final List<CollectionItem> items;
  final Color accentColor;
  final bool editable;
  final VoidCallback? onAdd;
  final void Function(String itemId)? onRemove;
  final void Function(List<String> orderedIds)? onReorderIds;

  const FavoritesShowcase({
    super.key,
    required this.items,
    required this.accentColor,
    this.editable = false,
    this.onAdd,
    this.onRemove,
    this.onReorderIds,
  });

  static const maxItems = 100;
  static const baseSize = 72.0;
  static const maxScale = 1.35;
  static const minScale = 0.55;

  @override
  State<FavoritesShowcase> createState() => _FavoritesShowcaseState();
}

class _FavoritesShowcaseState extends State<FavoritesShowcase> {
  final Map<String, ShowcaseLayoutItem> _layout = {};
  String? _selectedId;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(FavoritesShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureLayouts();
  }

  Future<void> _bootstrap() async {
    // Lazy: user id from items / prefs key shared.
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('showcase_layout_uid');
    await _loadLayout();
    _ensureLayouts();
    if (mounted) setState(() {});
  }

  String get _prefsKey => 'showcase_layout_v1_${_userId ?? 'local'}';

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).whereType<Map>();
      for (final m in list) {
        final item = ShowcaseLayoutItem.fromJson(Map<String, dynamic>.from(m));
        if (item.itemId.isNotEmpty) _layout[item.itemId] = item;
      }
    } catch (_) {}
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_layout.values.map((e) => e.toJson()).toList()),
    );
  }

  void _ensureLayouts() {
    var i = 0;
    for (final item in widget.items) {
      _layout.putIfAbsent(item.id, () {
        final col = i % 4;
        final row = i ~/ 4;
        i++;
        return ShowcaseLayoutItem(
          itemId: item.id,
          x: 12.0 + col * 86,
          y: 12.0 + row * 100,
          scale: 0.85,
        );
      });
      i++;
    }
    final keep = widget.items.map((e) => e.id).toSet();
    _layout.removeWhere((k, _) => !keep.contains(k));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  widget.accentColor.withValues(alpha: 0.22),
                  const Color(0xFF1A1A22),
                ]
              : [
                  widget.accentColor.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.55),
                ],
        ),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.25)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vitrine',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: widget.accentColor.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.items.length}/${FavoritesShowcase.maxItems} — glisse, pince, pivote',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.editable)
                    IconButton.filledTonal(
                      onPressed: widget.items.length >= FavoritesShowcase.maxItems
                          ? null
                          : widget.onAdd,
                      icon: const Icon(Icons.add),
                      tooltip: 'Ajouter',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 280,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        if (widget.items.isEmpty)
                          Center(
                            child: Text(
                              widget.editable
                                  ? 'Appuie sur + pour ajouter un objet'
                                  : 'Vitrine vide',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        for (final item in widget.items)
                          if (_layout[item.id] != null)
                            _FreeformTile(
                              item: item,
                              layout: _layout[item.id]!,
                              selected: _selectedId == item.id,
                              editable: widget.editable,
                              onSelect: () =>
                                  setState(() => _selectedId = item.id),
                              onChanged: () {
                                setState(() {});
                                _saveLayout();
                              },
                              onRemove: widget.editable
                                  ? () => widget.onRemove?.call(item.id)
                                  : null,
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.editable && _selectedId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Taille', style: TextStyle(color: scheme.onSurfaceVariant)),
                    Expanded(
                      child: Slider(
                        value: (_layout[_selectedId!]?.scale ?? 0.85)
                            .clamp(FavoritesShowcase.minScale, FavoritesShowcase.maxScale),
                        min: FavoritesShowcase.minScale,
                        max: FavoritesShowcase.maxScale,
                        onChanged: (v) {
                          setState(() => _layout[_selectedId!]!.scale = v);
                          _saveLayout();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pivoter',
                      onPressed: () {
                        setState(() {
                          _layout[_selectedId!]!.rotation += math.pi / 12;
                        });
                        _saveLayout();
                      },
                      icon: const Icon(Icons.rotate_right),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeformTile extends StatelessWidget {
  final CollectionItem item;
  final ShowcaseLayoutItem layout;
  final bool selected;
  final bool editable;
  final VoidCallback onSelect;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _FreeformTile({
    required this.item,
    required this.layout,
    required this.selected,
    required this.editable,
    required this.onSelect,
    required this.onChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final size = FavoritesShowcase.baseSize * layout.scale;
    return Positioned(
      left: layout.x,
      top: layout.y,
      child: GestureDetector(
        onTap: onSelect,
        onPanUpdate: editable
            ? (d) {
                layout.x += d.delta.dx;
                layout.y += d.delta.dy;
                onChanged();
              }
            : null,
        onLongPress: editable ? onRemove : null,
        child: Transform.rotate(
          angle: layout.rotation,
          child: Container(
            width: size,
            height: size * 1.35,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? CollectionCoverImage(
                    url: item.imageUrl!,
                    boxedCover: true,
                    compact: true,
                    fit: BoxFit.cover,
                  )
                : ColoredBox(
                    color: Colors.grey.shade800,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
          ),
        ),
      ),
    );
  }
}
