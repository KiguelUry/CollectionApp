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
    r'^(.*?)[,\s:-]+(?:vol\.?|volume|tome|#|n°|no\.?)\s*(\d+(?:[.,]\d+)?)\s*$',
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
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.endsWith(',')) s = s.substring(0, s.length - 1).trim();
    if (s.length < 2) return null;
    return s;
  }

  static double? _parseVolume(String raw) {
    final n = double.tryParse(raw.replaceAll(',', '.'));
    if (n == null || n < 0) return null;
    return n;
  }

  static bool seriesNamesMatch(String a, String b) {
    final na = a.toLowerCase().trim();
    final nb = b.toLowerCase().trim();
    if (na == nb) return true;
    return na.startsWith(nb) || nb.startsWith(na);
  }
}
