import 'collection_item.dart';

/// État d'un emplacement tome/chapitre dans la grille.
enum BookVolumeStatus {
  missing,
  owned,
  wishlist,
}

class BookVolume {
  final String id;
  final String seriesId;
  final double volumeNumber;
  final String? label;
  final double sortIndex;
  final Map<String, dynamic> metadata;

  const BookVolume({
    required this.id,
    required this.seriesId,
    required this.volumeNumber,
    this.label,
    required this.sortIndex,
    this.metadata = const {},
  });

  String? get coverUrl {
    final url = metadata['cover_url'] as String?;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  String get displayNumber {
    if (volumeNumber == volumeNumber.roundToDouble()) {
      return volumeNumber.toInt().toString();
    }
    return volumeNumber.toString();
  }

  factory BookVolume.fromJson(Map<String, dynamic> json) {
    return BookVolume(
      id: json['id'] as String,
      seriesId: json['series_id'] as String,
      volumeNumber: (json['volume_number'] as num).toDouble(),
      label: json['label'] as String?,
      sortIndex: (json['sort_index'] as num).toDouble(),
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'series_id': seriesId,
        'volume_number': volumeNumber,
        'label': label,
        'sort_index': sortIndex,
        'metadata': metadata,
      };
}

class BookVolumeSlot {
  final BookVolume volume;
  final CollectionItem? item;
  final BookVolumeStatus status;

  const BookVolumeSlot({
    required this.volume,
    this.item,
    required this.status,
  });
}
