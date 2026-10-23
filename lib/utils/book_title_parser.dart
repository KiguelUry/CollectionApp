/// Extrait série + numéro de tome depuis un titre (Naruto, Vol. 13…).
class ParsedBookTitle {
  final String rawTitle;
  final String? seriesName;
  final double? volumeNumber;

  const ParsedBookTitle({
    required this.rawTitle,
    this.seriesName,
    this.volumeNumber,
  });

  bool get hasSeries =>
      seriesName != null && seriesName!.trim().length >= 2;

  bool get hasVolume => volumeNumber != null;

  String get itemTitle {
    if (hasSeries && hasVolume) {
      final n = volumeNumber!;
      final numLabel = n == n.roundToDouble()
          ? n.toInt().toString()
          : n.toString();
      return '${seriesName!.trim()} - Tome $numLabel';
    }
    return rawTitle.trim();
  }
}

abstract final class BookTitleParser {
  static final _volumePrefix = RegExp(
    r'^(.*?)[,\s:-]+(?:vol\.?|volume|tome|t\.?|#|n°|no\.?)\s*(\d+(?:[.,]\d+)?)\s*$',
    caseSensitive: false,
  );

  static final _hashVolume = RegExp(
    r'^(.*?)\s*#\s*(\d+(?:[.,]\d+)?)\s*$',
    caseSensitive: false,
  );

  static final _trailingNumber = RegExp(
    r'^(.*?)\s+(\d{1,3})(?:\s*$|\s*[-–])',
    caseSensitive: false,
  );

  static final _stripSuffix = RegExp(
    r'\s*(?:\(.*\)|\[.*\]|\{.*\})\s*$',
  );

  static ParsedBookTitle parse(String title) {
    var t = title.trim();
    if (t.isEmpty) {
      return ParsedBookTitle(rawTitle: title);
    }
    // Normalise tirets typographiques (– — −) → ASCII pour le parseur.
    t = t.replaceAll(RegExp(r'[–—−]'), '-');
    t = t.replaceAll(_stripSuffix, '').trim();

    for (final pattern in [_volumePrefix, _hashVolume]) {
      final m = pattern.firstMatch(t);
      if (m != null) {
        final series = _cleanSeriesName(m.group(1)!);
        final vol = _parseVolume(m.group(2)!);
        if (series != null && vol != null) {
          return ParsedBookTitle(
            rawTitle: title,
            seriesName: series,
            volumeNumber: vol,
          );
        }
      }
    }

    final trail = _trailingNumber.firstMatch(t);
    if (trail != null) {
      final series = _cleanSeriesName(trail.group(1)!);
      final vol = _parseVolume(trail.group(2)!);
      if (series != null &&
          vol != null &&
          series.length >= 3 &&
          vol >= 1 &&
          vol <= 200) {
        return ParsedBookTitle(
          rawTitle: title,
          seriesName: series,
          volumeNumber: vol,
        );
      }
    }

    return ParsedBookTitle(rawTitle: title);
  }

  static String? _cleanSeriesName(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[–—−]'), '-');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    // Enlève tirets / ponctuation orphelins en fin (« Thorgal - »).
    s = s.replaceAll(RegExp(r'[\s,;:\-]+$'), '').trim();
    if (s.endsWith(',')) s = s.substring(0, s.length - 1).trim();
    if (s.length < 2) return null;
    return s;
  }

  static double? _parseVolume(String raw) {
    final n = double.tryParse(raw.replaceAll(',', '.'));
    if (n == null || n < 0) return null;
    return n;
  }

  /// Extrait le n° de tome avec borne stricte (1 ≠ 16, 1 ≠ 17).
  static int? extractVolumeNumberStrict(String title) {
    final m = RegExp(
      r'\b(?:tome|vol\.?|volume|t\.?)\s*0*(\d+)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// Vrai seulement si le titre référence exactement [targetVolume].
  static bool titleMatchesVolumeExactly(String title, int targetVolume) {
    if (targetVolume < 0) return false;
    final re = RegExp(
      r'\b(?:tome|vol\.?|volume|t\.?)\s*0*'
      '${RegExp.escape('$targetVolume')}'
      r'(?!\d)\b',
      caseSensitive: false,
    );
    if (!re.hasMatch(title)) return false;
    final extracted = extractVolumeNumberStrict(title);
    return extracted == targetVolume;
  }

  static bool seriesNamesMatch(String a, String b) {
    final na = _normName(a);
    final nb = _normName(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    return na.startsWith(nb) || nb.startsWith(na);
  }

  static String _normName(String s) {
    var n = s.toLowerCase().trim();
    n = n.replaceAll(RegExp(r'[–—−]'), '-');
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    n = n.replaceAll(RegExp(r'[\s\-]+$'), '');
    return n;
  }
}
