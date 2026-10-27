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
  /// « Tome N » / « Vol. N » / « Book N » n'importe où (romans SEO, sous-titres).
  static final _volumeAnywhere = RegExp(
    r'(?:^|[\s,;:\-–—\[\(])(?:tome|volume|vol\.?|book|livre|t\.?)\s*(\d{1,4})\b',
    caseSensitive: false,
  );

  /// Ancre fin de chaîne (manga classique).
  static final _volumePrefix = RegExp(
    r'^(.*?)[,\s:-]+(?:vol\.?|volume|tome|t\.?|#|n°|no\.?)\s*(\d+(?:[.,]\d+)?)\s*$',
    caseSensitive: false,
  );

  /// Compact VF : « Kagurabachi T10 » / « Kagurabachi T.11 ».
  static final _compactTVolume = RegExp(
    r'^(.*?)\s+t\.?\s*(\d{1,3})\s*$',
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

    // 1) Mid-string d'abord : « … - Tome 2 : SEO… », « … : Sous-titre - Tome 3 ».
    final mid = _parseVolumeAnywhere(title, t);
    if (mid != null) return mid;

    t = t.replaceAll(_stripSuffix, '').trim();

    for (final pattern in [_volumePrefix, _compactTVolume, _hashVolume]) {
      final m = pattern.firstMatch(t);
      if (m != null) {
        final series = _canonicalSeriesName(m.group(1)!);
        final vol = _parseVolume(m.group(2)!);
        if (series != null && vol != null && _isPlausibleVolume(vol)) {
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
      final series = _canonicalSeriesName(trail.group(1)!);
      final vol = _parseVolume(trail.group(2)!);
      if (series != null &&
          vol != null &&
          series.length >= 3 &&
          _isPlausibleVolume(vol)) {
        return ParsedBookTitle(
          rawTitle: title,
          seriesName: series,
          volumeNumber: vol,
        );
      }
    }

    return ParsedBookTitle(rawTitle: title);
  }

  /// Trouve le premier `Tome|Vol|Book|Livre|T. N` avec N < 1900.
  static ParsedBookTitle? _parseVolumeAnywhere(String rawTitle, String t) {
    for (final m in _volumeAnywhere.allMatches(t)) {
      final vol = _parseVolume(m.group(1)!);
      if (vol == null || !_isPlausibleVolume(vol)) continue;
      var before = t.substring(0, m.start).trim();
      before = before.replaceAll(RegExp(r'[\s,;:\-\[\(]+$'), '').trim();
      final series = _canonicalSeriesName(before);
      if (series == null) continue;
      return ParsedBookTitle(
        rawTitle: rawTitle,
        seriesName: series,
        volumeNumber: vol,
      );
    }
    return null;
  }

  /// Coupe au premier `:` si présent (« Dungeon Crawler Carl : L'Ogive… »).
  static String? _canonicalSeriesName(String raw) {
    var s = _cleanSeriesName(raw);
    if (s == null) return null;
    final colon = s.indexOf(':');
    if (colon > 1) {
      final head = _cleanSeriesName(s.substring(0, colon));
      if (head != null && head.length >= 2) return head;
    }
    return s;
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

  /// Ignore les années (2024/2025…) prises pour un n° de tome.
  static bool _isPlausibleVolume(double n) => n >= 1 && n < 1900 && n <= 500;

  /// Extrait le n° de tome avec borne stricte (1 ≠ 16 ; matche aussi `T10`).
  static int? extractVolumeNumberStrict(String title) {
    final normalized = title.replaceAll(RegExp(r'[–—−]'), '-');
    for (final m in _volumeAnywhere.allMatches(normalized)) {
      final n = int.tryParse(m.group(1)!);
      if (n == null || n < 1 || n >= 1900) continue;
      return n;
    }
    final m = RegExp(
      r'\b(?:tome|vol\.?|volume|t\.?)\s*0*(\d+)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null || n >= 1900) return null;
    return n;
  }

  /// Vrai seulement si le titre référence exactement [targetVolume]
  /// (`Tome 10`, `T10`, `T.10`, `Vol. 10` — pas `Tome 16` pour 1).
  static bool titleMatchesVolumeExactly(String title, int targetVolume) {
    if (targetVolume < 0 || targetVolume >= 1900) return false;
    final re = RegExp(
      r'\b(?:tome|vol\.?|volume|book|livre|t\.?)\s*0*'
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
