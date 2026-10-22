import 'package:flutter/material.dart';

import '../models/collection_item.dart';
import '../utils/item_favorite.dart';

/// Cœur favori synchronisé (grille, fiche, sheet notes).
class FavoriteHeartButton extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;
  final EdgeInsetsGeometry padding;
  final ValueChanged<CollectionItem>? onChanged;

  const FavoriteHeartButton({
    super.key,
    required this.item,
    this.readOnly = false,
    this.size = 18,
    this.activeColor,
    this.inactiveColor,
    this.padding = const EdgeInsets.all(4),
    this.onChanged,
  });

  @override
  State<FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<FavoriteHeartButton> {
  late bool _fav;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fav = widget.item.isFavorite;
  }

  @override
  void didUpdateWidget(covariant FavoriteHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.isFavorite != widget.item.isFavorite) {
      _fav = widget.item.isFavorite;
    }
  }

  Future<void> _toggle() async {
    if (widget.readOnly || _saving) return;
    final next = !_fav;
    setState(() {
      _fav = next;
      _saving = true;
    });
    try {
      final updated = await toggleItemFavorite(widget.item);
      widget.onChanged?.call(updated);
    } catch (_) {
      if (mounted) {
        setState(() => _fav = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de mettre à jour le favori')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeColor ?? Colors.redAccent;
    final inactive = widget.inactiveColor ?? Colors.white;
    final tooltip = widget.item.isWishlist
        ? (_fav ? 'Retirer la priorité' : 'Priorité / Coup de cœur')
        : (_fav ? 'Retirer des favoris' : 'Ajouter aux favoris');
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: widget.readOnly ? null : _toggle,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: widget.padding,
            child: Icon(
              _fav ? Icons.favorite : Icons.favorite_border,
              size: widget.size,
              color: _fav ? active : inactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// Variante plate (sans pastille sombre) pour sheets / app bars.
class FavoriteHeartIconButton extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<CollectionItem>? onChanged;

  const FavoriteHeartIconButton({
    super.key,
    required this.item,
    this.readOnly = false,
    this.onChanged,
  });

  @override
  State<FavoriteHeartIconButton> createState() =>
      _FavoriteHeartIconButtonState();
}

class _FavoriteHeartIconButtonState extends State<FavoriteHeartIconButton> {
  late bool _fav;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fav = widget.item.isFavorite;
  }

  @override
  void didUpdateWidget(covariant FavoriteHeartIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.isFavorite != widget.item.isFavorite) {
      _fav = widget.item.isFavorite;
    }
  }

  Future<void> _toggle() async {
    if (widget.readOnly || _saving) return;
    final next = !_fav;
    setState(() {
      _fav = next;
      _saving = true;
    });
    try {
      final updated = await toggleItemFavorite(widget.item);
      widget.onChanged?.call(updated);
    } catch (_) {
      if (mounted) {
        setState(() => _fav = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de mettre à jour le favori')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlist = widget.item.isWishlist;
    return IconButton(
      tooltip: wishlist
          ? (_fav ? 'Retirer la priorité' : 'Priorité / Coup de cœur')
          : (_fav ? 'Retirer des favoris' : 'Ajouter aux favoris'),
      onPressed: widget.readOnly ? null : _toggle,
      icon: Icon(
        _fav ? Icons.favorite : Icons.favorite_border,
        color: _fav ? Colors.redAccent : null,
      ),
    );
  }
}
