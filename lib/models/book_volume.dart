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

  bool get isRead => metadata['is_read'] == true;

  bool get isManualPlaceholder => metadata['is_manual_placeholder'] == true;

  bool get isHorsSerie => metadata['is_hors_serie'] == true;

  String? get volumeTitle {
    final fromMeta = metadata['volume_title']?.toString().trim();
    if (fromMeta != null && fromMeta.isNotEmpty && !_isGenericLabel(fromMeta)) {
      return fromMeta;
    }
    final lbl = label?.trim();
    if (lbl != null && lbl.isNotEmpty && !_isGenericLabel(lbl)) {
      return lbl;
    }
    return null;
  }

  static bool _isGenericLabel(String value) {
    final s = value.trim();
    if (s.isEmpty) return true;
    if (RegExp(r'^\d+$').hasMatch(s)) return true;
    if (RegExp(r'^tome\s+\d+([.,]\d+)?$', caseSensitive: false).hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^t\.\s*\d+([.,]\d+)?$', caseSensitive: false).hasMatch(s)) {
      return true;
    }
    return false;
  }

  String? get description {
    final d = metadata['description']?.toString();
    if (d == null || d.trim().isEmpty) return null;
    return d.trim();
  }

  String get displayNumber {
    if (isHorsSerie) return 'HS';
    if (volumeNumber == volumeNumber.roundToDouble()) {
      return volumeNumber.toInt().toString();
    }
    return volumeNumber.toString();
  }

  /// Libellé grille : « T.X - Le Nom du Tome » ou « Tome X ».
  String get displayTitle {
    if (isHorsSerie) {
      final t = volumeTitle;
      return t != null && t.isNotEmpty ? t : 'Hors-série';
    }
    final title = volumeTitle;
    if (title != null && title.isNotEmpty) {
      return 'T.$displayNumber - $title';
    }
    return 'Tome $displayNumber';
  }

  BookVolume copyWithMetadata(Map<String, dynamic> patch) {
    return BookVolume(
      id: id,
      seriesId: seriesId,
      volumeNumber: volumeNumber,
      label: label,
      sortIndex: sortIndex,
      metadata: {...metadata, ...patch},
    );
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
