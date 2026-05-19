import 'package:flutter/material.dart';

import '../models/book_volume.dart';
import '../widgets/collection_cover_image.dart';

String? volumeCoverUrl(BookVolumeSlot slot) {
  final fromVolume = slot.volume.coverUrl;
  if (fromVolume != null && fromVolume.isNotEmpty) return fromVolume;
  final fromItem = slot.item?.imageUrl;
  if (fromItem != null && fromItem.isNotEmpty) return fromItem;
  return null;
}

/// Vignette tome : couverture si dispo, sinon pastille numérotée.
class VolumeLeading extends StatelessWidget {
  final BookVolumeSlot slot;
  final Color fallbackColor;

  const VolumeLeading({
    super.key,
    required this.slot,
    required this.fallbackColor,
  });

  static const _w = 40.0;
  static const _h = 58.0;

  @override
  Widget build(BuildContext context) {
    final cover = volumeCoverUrl(slot);
    if (cover != null) {
      return CollectionCoverImage(
        url: cover,
        width: _w,
        height: _h,
        bookCover: true,
      );
    }
    return _numberedBox();
  }

  Widget _numberedBox() {
    return Container(
      width: _w,
      height: _h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fallbackColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        slot.volume.displayNumber,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
