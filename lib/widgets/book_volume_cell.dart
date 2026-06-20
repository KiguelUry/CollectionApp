import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_volume.dart';

/// Cellule visuelle d'un tome (Possédé × Lu).
class BookVolumeCell extends StatelessWidget {
  final BookVolumeSlot slot;
  final Color accent;
  final VoidCallback? onToggleOwned;
  final VoidCallback? onToggleRead;
  final VoidCallback? onQuickAdd;

  const BookVolumeCell({
    super.key,
    required this.slot,
    this.accent = BookAccent.primary,
    this.onToggleOwned,
    this.onToggleRead,
    this.onQuickAdd,
  });

  bool get _owned =>
      slot.item != null && !slot.item!.isWishlist;

  bool get _read => _owned && slot.item!.isRead;

  bool get _missing => slot.item == null;

  @override
  Widget build(BuildContext context) {
    final n = slot.volume.displayNumber;
    final cover = slot.volume.coverUrl;

    return Material(
      color: _owned ? accent.withValues(alpha: 0.08) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _missing ? onQuickAdd : onToggleOwned,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: cover != null && cover.isNotEmpty
                          ? Image.network(
                              cover,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(n),
                            )
                          : _placeholder(n),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'T. $n',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _owned ? accent : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            if (!_missing) ...[
              Positioned(
                top: 4,
                right: 4,
                child: _StatusBadge(
                  icon: Icons.home_rounded,
                  active: _owned,
                  activeColor: accent,
                  onTap: onToggleOwned,
                ),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: _StatusBadge(
                  icon: Icons.visibility_rounded,
                  active: _read,
                  activeColor: Colors.amber.shade800,
                  onTap: _owned ? onToggleRead : null,
                ),
              ),
            ],
            if (_missing && onQuickAdd != null)
              Positioned(
                bottom: 28,
                right: 6,
                child: Material(
                  color: accent,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onQuickAdd,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.add, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String n) {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Text(
        n,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _StatusBadge({
    required this.icon,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? activeColor : Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
