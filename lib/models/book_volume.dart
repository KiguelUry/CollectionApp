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
    final raw = metadata['cover_url'];
    if (raw == null) return null;
    final url = raw.toString().trim();
    if (url.isEmpty) return null;
    return url;
  }

  bool get isRead => metadata['is_read'] == true;

  bool get isManualPlaceholder => metadata['is_manual_placeholder'] == true;

  bool get isHorsSerie => metadata['is_hors_serie'] == true;

  /// Chapitre / scan unitaire (pas un tome relié physique).
  bool get isChapterOrScan {
    if (metadata['is_chapter'] == true || metadata['is_scan'] == true) {
      return true;
    }
    final blob =
        '${label ?? ''} ${volumeTitle ?? ''} ${metadata['source_title'] ?? ''} '
        '${metadata['raw_title'] ?? ''}';
    final t = blob.toLowerCase();
    if (RegExp(
      r'\b(?:chapitre|chapter|chap\.?|ch\.?|épisode|episode|ep\.)\s*\d+',
      caseSensitive: false,
    ).hasMatch(t)) {
      if (RegExp(r'\b(?:tome|vol\.?|volume)\s*\d+', caseSensitive: false)
          .hasMatch(t)) {
        return false;
      }
      return true;
    }
    return RegExp(r'\b(?:scan|scanlation|webtoon)\b', caseSensitive: false)
        .hasMatch(t);
  }

  /// Date de parution catalogue (ISO / YYYY-MM-DD / YYYY).
  DateTime? get publishedDate {
    final raw = metadata['published_date']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final full = DateTime.tryParse(raw);
    if (full != null) return full;
    if (RegExp(r'^\d{4}-\d{2}$').hasMatch(raw)) {
      return DateTime.tryParse('$raw-01');
    }
    if (RegExp(r'^\d{4}$').hasMatch(raw)) {
      return DateTime.tryParse('$raw-01-01');
    }
    return null;
  }

  /// Tome pas encore sorti. La date doit être strictement après aujourd'hui + 2 jours.
  /// Un flag `is_upcoming` sans date future ne suffit pas.
  bool get isUpcoming {
    final d = publishedDate;
    if (d == null) return false;
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 2));
    return d.isAfter(cutoff);
  }

  String? get upcomingLabel {
    if (!isUpcoming) return null;
    final d = publishedDate;
    if (d == null) return '⏳ À paraître';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '⏳ À paraître · $dd/$mm/${d.year}';
  }

  /// Édition physique / numérique (metadata `edition`).
  BookVolumeEdition get edition =>
      BookVolumeEdition.fromMeta(metadata['edition']?.toString());

  /// `fr` (défaut), `ja` ou `en`.
  String get editionLanguage {
    final raw = metadata['edition_language']?.toString().trim().toLowerCase();
    if (raw == 'ja' || raw == 'jp') return 'ja';
    if (raw == 'en') return 'en';
    if (raw == 'other' || raw == 'autre') return 'other';
    return 'fr';
  }

  String? get editionBadge {
    return switch (edition) {
      BookVolumeEdition.collector => '✨ Collector',
      BookVolumeEdition.firstEdition => 'EO',
      BookVolumeEdition.boxset => '📚 Coffret',
      BookVolumeEdition.digital => '🌐 Scan',
      BookVolumeEdition.standard => null,
    };
  }

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
      metadata: {
        ...metadata,
        ...patch,
      }..removeWhere((k, v) => patch.containsKey(k) && v == null),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _double(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static Map<String, dynamic> _map(dynamic v) {
    if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
    if (v is Map) return Map<String, dynamic>.from(v);
    return const {};
  }

  factory BookVolume.fromJson(Map<String, dynamic> json) {
    final volume = _double(json['volume_number']) ?? 0;
    return BookVolume(
      id: _str(json['id']) ?? '',
      seriesId: _str(json['series_id']) ?? '',
      volumeNumber: volume,
      label: _str(json['label']),
      sortIndex: _double(json['sort_index']) ?? volume,
      metadata: _map(json['metadata']),
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

enum BookVolumeEdition {
  standard,
  collector,
  firstEdition,
  boxset,
  digital;

  String get dbValue => switch (this) {
        BookVolumeEdition.standard => 'standard',
        BookVolumeEdition.collector => 'collector',
        BookVolumeEdition.firstEdition => 'first',
        BookVolumeEdition.boxset => 'boxset',
        BookVolumeEdition.digital => 'digital',
      };

  String get label => switch (this) {
        BookVolumeEdition.standard => '📗 Standard',
        BookVolumeEdition.collector => '✨ Édition Spéciale / Collector',
        BookVolumeEdition.firstEdition => '🥇 1ère Édition (EO)',
        BookVolumeEdition.boxset => '📚 Coffret / Intégrale',
        BookVolumeEdition.digital => '🌐 Numérique / Scan',
      };

  static BookVolumeEdition fromMeta(String? raw) {
    return switch (raw) {
      'collector' => BookVolumeEdition.collector,
      'first' => BookVolumeEdition.firstEdition,
      'boxset' => BookVolumeEdition.boxset,
      'digital' => BookVolumeEdition.digital,
      _ => BookVolumeEdition.standard,
    };
  }
}
