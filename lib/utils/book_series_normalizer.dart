import '../models/book_subcategory.dart';
import 'book_title_parser.dart';

/// Normalise titres livres → (série, tome). Catégorie / compteurs = API + éditeurs.
abstract final class BookSeriesNormalizer {
  /// Éditeurs manga FR / US (heuristique éditeur, jamais titre de série).
  static const mangaPublishers = <String>{
    'meian',
    'kana',
    'ki-oon',
    'ki oon',
    'kurokawa',
    'pika',
    'panini manga',
    'crunchyroll',
    'kazé',
    'kaze',
    'glénat manga',
    'glenat manga',
    'delcourt/tonkam',
    'delcourt tonkam',
    'tonkam',
    'soleil manga',
    'akata',
    'ototo',
    'taifu',
    'mangetsu',
    'noeve',
    'noeve grafx',
    'vega',
    'viz',
    'viz media',
    'shonen jump',
    'kodansha',
    'shueisha',
    'ankama',
  };

  /// Éditeurs BD franco-belge.
  static const bdPublishers = <String>{
    'le lombard',
    'lombard',
    'dargaud',
    'dupuis',
    'casterman',
    'delcourt',
    'soleil',
    'fluide glacial',
    'glénat',
    'glenat',
    'bamboo',
    'rue de sèvres',
    'rue de sevres',
    'futuropolis',
    'dupuis / marsu',
    'ankama',
  };

  /// Éditeurs comics US.
  static const comicsPublishers = <String>{
    'urban comics',
    'marvel',
    'dc',
    'dc comics',
    'image comics',
    'dark horse',
    'idw',
    'boom! studios',
    'panini comics',
  };

  /// Déduit Manga / BD / Comics depuis éditeur + subjects API (jamais une liste de titres).
  static BookSubcategory? detectSubcategory({
    String? seriesName,
    String? title,
    String? publisher,
    String? subjects,
  }) {
    final pub = (publisher ?? '').toLowerCase().trim();
    if (pub.isNotEmpty) {
      // « Glénat Manga » / « Soleil Manga » avant « Glénat » / « Soleil » seuls.
      if (mangaPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.manga;
      }
      if (comicsPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.comics;
      }
      if (bdPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.comic;
      }
    }

    final subj = (subjects ?? '').toLowerCase();
    final blob = '$subj ${title ?? ''} ${seriesName ?? ''}'.toLowerCase();
    if (subj.contains('manga') ||
        subj.contains('anime') ||
        RegExp(r'\bmanga\b').hasMatch(blob) &&
            pub.contains('manga')) {
      if (subj.contains('manga') || subj.contains('anime')) {
        return BookSubcategory.manga;
      }
    }
    if (subj.contains('manga') || subj.contains('anime')) {
      return BookSubcategory.manga;
    }
    if (subj.contains('comic') || subj.contains('superhero')) {
      return BookSubcategory.comics;
    }
    if (subj.contains('bande dessinée') ||
        subj.contains('bande dessinee') ||
        subj.contains('graphic novel') ||
        subj.contains('comics & graphic novels - european')) {
      return BookSubcategory.comic;
    }
    return null;
  }

  /// @Deprecated — plus de liste de titres. Toujours null (catégorie = éditeur/API).
  static BookSubcategory? preferredSubcategory(String seriesName) => null;

  /// @Deprecated — plus de dictionnaire de tomes. Toujours null (AniList / max hits).
  static int? expectedCount(String seriesName, [BookSubcategory? subcategory]) =>
      null;

  /// Clé de fusion (ignore « - Tome N »).
  static String mergeKey(String rawName) {
    final display = displaySeriesName(rawName);
    return normalizeKey(display);
  }

  static ParsedBookTitle parse(String title) => BookTitleParser.parse(title);

  static String normalizeKey(String name) {
    var s = name.toLowerCase().trim();
    s = s
        .replaceAll(RegExp(r'[–—−]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^the\s+'), '')
        .replaceAll(RegExp(r'^les?\s+'), '');
    return s;
  }

  static bool namesMatch(String a, String b) =>
      BookTitleParser.seriesNamesMatch(normalizeKey(a), normalizeKey(b)) ||
      BookTitleParser.seriesNamesMatch(a, b);

  /// Vrai si le titre du hit appartient strictement à la série [seriesName].
  static bool hitBelongsToSeries(String hitTitle, String seriesName) {
    final want = normalizeKey(
      stripEditionSuffix(stripOrphanVolumeSuffix(seriesName)),
    );
    if (want.isEmpty) return false;
    final parsed = parse(hitTitle);
    final extracted = parsed.hasSeries
        ? normalizeKey(stripEditionSuffix(parsed.seriesName!))
        : normalizeKey(stripEditionSuffix(stripOrphanVolumeSuffix(hitTitle)));
    if (extracted.isEmpty) return false;
    return extracted == want;
  }

  /// Titre qui ressemble à un chapitre / scan unitaire (pas un tome relié).
  static bool looksLikeChapterOrScan(String title) {
    final t = title.toLowerCase();
    if (RegExp(
      r'\b(?:chapitre|chapter|chap\.?|ch\.?)\s*\d+',
      caseSensitive: false,
    ).hasMatch(t)) {
      // « Tome » + « Chapitre » dans le même titre = souvent un omnibus / faux positif.
      if (RegExp(r'\b(?:tome|vol\.?|volume)\s*\d+', caseSensitive: false)
          .hasMatch(t)) {
        return false;
      }
      return true;
    }
    if (RegExp(r'\b(?:scan|scanlation|webtoon)\b', caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    return false;
  }

  static String normalizeAuthorKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sàâäéèêëïîôùûüç]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool authorsMatch(String? a, String? b) {
    final na = normalizeAuthorKey(a ?? '');
    final nb = normalizeAuthorKey(b ?? '');
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.contains(nb) || nb.contains(na)) return true;
    final ta = na.split(' ').where((t) => t.isNotEmpty).toList();
    final tb = nb.split(' ').where((t) => t.isNotEmpty).toList();
    if (ta.isNotEmpty &&
        tb.isNotEmpty &&
        ta.last == tb.last &&
        ta.last.length >= 3) {
      return true;
    }
    final sa = ta.where((t) => t.length >= 4).toSet();
    final sb = tb.where((t) => t.length >= 4).toSet();
    return sa.intersection(sb).isNotEmpty;
  }

  static bool authorMatchesExpected(String? hitAuthor, String? expectedAuthor) {
    if (expectedAuthor == null || expectedAuthor.trim().isEmpty) return true;
    return authorsMatch(hitAuthor, expectedAuthor);
  }

  static String seriesAuthorKey(String seriesName, String? author) {
    final s = mergeKey(seriesName);
    final a = normalizeAuthorKey(author ?? '');
    return a.isEmpty ? s : '$s|$a';
  }

  static String displaySeriesName(String rawTitle) {
    final parsed = parse(rawTitle);
    var name = parsed.hasSeries
        ? parsed.seriesName!.trim()
        : rawTitle.trim();
    name = stripOrphanVolumeSuffix(name);
    return stripEditionSuffix(name);
  }

  static String stripOrphanVolumeSuffix(String name) {
    var s = name.trim().replaceAll(RegExp(r'[–—−]'), '-');
    s = s.replaceAll(
      RegExp(
        r'\s*(?:-|–|—)?\s*(?:tome|tomes|vol\.?|volume|volumes|t\.?)\s*\d*\s*$',
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(RegExp(r'[\s,;:\-]+$'), '').trim();
    return s.isEmpty ? name.trim() : s;
  }

  static String stripEditionSuffix(String name) {
    var s = name.trim().replaceAll(RegExp(r'[–—−]'), '-');
    s = s.replaceAll(
      RegExp(
        r'\s*(?:-|–|—)?\s*(?:édition|edition)\s+'
        r'(?:originale|original|collector|spéciale|speciale|intégrale|integrale)\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'\s*(?:-|–|—)?\s*(?:édition|edition)\s+\S+.*$',
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'\s*(?:-|–|—)?\s*(?:omnibus|coffret|box\s*set)\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    return s.replaceAll(RegExp(r'[\s,;:\-]+$'), '').trim();
  }

  static String googleBooksCoverQuery({
    required String seriesTitle,
    int? volumeNumber,
    String? author,
  }) {
    final title = coverSearchSeriesName(seriesTitle);
    final parts = <String>[
      if (volumeNumber != null && volumeNumber > 0)
        'intitle:"$title" intitle:"Tome $volumeNumber"'
      else
        'intitle:"$title"',
      if (author != null && author.trim().isNotEmpty)
        'inauthor:"${author.trim()}"',
    ];
    return parts.join(' ');
  }

  static String coverSearchSeriesName(String raw) => displaySeriesName(raw);

  static ({String seriesQuery, int? volumeNumber}) parseCatalogSearchQuery(
    String raw,
  ) {
    final t = raw.trim();
    if (t.isEmpty) return (seriesQuery: '', volumeNumber: null);
    final parsed = parse(t);
    if (parsed.hasSeries && parsed.hasVolume) {
      return (
        seriesQuery: displaySeriesName(parsed.seriesName!),
        volumeNumber: parsed.volumeNumber!.round(),
      );
    }
    return (seriesQuery: displaySeriesName(t), volumeNumber: null);
  }

  /// Max des n° de tome parmi des hits appartenant au couple (série, auteur).
  static int maxVolumeAmongHits({
    required Iterable<({String title, String? author, int? volume})> hits,
    required String seriesName,
    String? author,
  }) {
    var max = 0;
    for (final h in hits) {
      if (!hitBelongsToSeries(h.title, seriesName)) continue;
      if (!authorMatchesExpected(h.author, author)) continue;
      if (looksLikeChapterOrScan(h.title)) continue;
      final n = h.volume ?? 0;
      if (n > max) max = n;
    }
    return max;
  }
}
