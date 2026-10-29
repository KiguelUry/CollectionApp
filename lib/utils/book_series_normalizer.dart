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
  /// Pas de « glénat » / « glenat » seuls : Glénat publie aussi du manga
  /// (Berserk, etc.) — la réconciliation AniList/MangaDex force Manga.
  /// Delcourt / Glénat : BD par défaut, Comics si subjects/auteur US.
  static const bdPublishers = <String>{
    'le lombard',
    'lombard',
    'dargaud',
    'dupuis',
    'casterman',
    'soleil',
    'fluide glacial',
    'bamboo',
    'rue de sèvres',
    'rue de sevres',
    'futuropolis',
    'dupuis / marsu',
    'humanoïdes associés',
    'humanoïdes associes',
    'les humanoïdes',
    'vents d\'ouest',
    'vents d ouest',
    'delsol',
  };

  /// Éditeurs ambigus (BD et comics).
  static const mixedFrancoPublishers = <String>{
    'delcourt',
    'glénat',
    'glenat',
  };

  /// Éditeurs comics US.
  static const comicsPublishers = <String>{
    'urban comics',
    'marvel',
    'dc',
    'dc comics',
    'image comics',
    'image',
    'dark horse',
    'skybound',
    'vault',
    'idw',
    'boom! studios',
    'panini comics',
    'panini',
  };

  /// Auteurs comics US fréquents (Walking Dead, Sin City, Watchmen…).
  static const comicsAuthors = <String>{
    'kirkman',
    'frank miller',
    'alan moore',
    'stan lee',
    'jack kirby',
    'todd mcfarlane',
    'neil gaiman',
  };

  /// Auteurs BD franco-belge fréquents.
  static const bdAuthors = <String>{
    'van hamme',
    'jean van hamme',
    'william vance',
  };

  /// « A, B & C » à partir d’une liste d’auteurs/dessinateurs.
  static String formatAuthorList(Iterable<String> names) {
    final unique = <String>[];
    final seen = <String>{};
    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      final k = normalizeAuthorKey(t);
      if (k.isEmpty || !seen.add(k)) continue;
      unique.add(t);
    }
    if (unique.isEmpty) return '';
    if (unique.length == 1) return unique.first;
    if (unique.length == 2) return '${unique[0]} & ${unique[1]}';
    return '${unique.sublist(0, unique.length - 1).join(', ')} & ${unique.last}';
  }

  static String? preferRicherAuthor(String? a, String? b) {
    final aa = a?.trim() ?? '';
    final bb = b?.trim() ?? '';
    if (aa.isEmpty) return bb.isEmpty ? null : bb;
    if (bb.isEmpty) return aa;
    return bb.split(RegExp(r'[,&]')).length > aa.split(RegExp(r'[,&]')).length
        ? bb
        : aa;
  }

  /// Déduit Manga / BD / Comics depuis éditeur + subjects API (jamais une liste de titres).
  /// BD et Comics **avant** Roman (un éditeur franco-belge ne doit jamais
  /// retomber en roman à cause d’un subject « fiction »).
  static BookSubcategory? detectSubcategory({
    String? seriesName,
    String? title,
    String? publisher,
    String? subjects,
    String? author,
    bool comicsContent = false,
  }) {
    final pub = (publisher ?? '').toLowerCase().trim();
    final subj = (subjects ?? '').toLowerCase();
    final blob = '$subj ${title ?? ''} ${seriesName ?? ''}'.toLowerCase();
    final authorKey = normalizeAuthorKey(author ?? '');

    if (pub.isNotEmpty) {
      // « Glénat Manga » / « Soleil Manga » / « Panini Manga » avant le reste.
      if (mangaPublishers.any((p) => pub.contains(p))) {
        return BookSubcategory.manga;
      }
    }

    if (subj.contains('manga') || subj.contains('anime')) {
      return BookSubcategory.manga;
    }

    final looksComicsSubj = comicsContent ||
        subj.contains('comics') ||
        subj.contains('superhero') ||
        subj.contains('super-hero') ||
        subj.contains('graphic novel');
    final looksBdSubj = subj.contains('bande dessinée') ||
        subj.contains('bande dessinee') ||
        RegExp(r'\bbd\b').hasMatch(subj) ||
        subj.contains('european');
    final usComicsAuthor = authorKey.isNotEmpty &&
        comicsAuthors.any((a) => authorKey.contains(a));
    final francoBdAuthor = authorKey.isNotEmpty &&
        bdAuthors.any((a) => authorKey.contains(a));
    final comicsPublisher = pub.isNotEmpty &&
        comicsPublishers.any((p) => pub.contains(p)) &&
        !pub.contains('manga');
    final bdPublisher = pub.isNotEmpty &&
        bdPublishers.any((p) => pub.contains(p));
    final mixedPublisher = pub.isNotEmpty &&
        mixedFrancoPublishers.any((p) => pub.contains(p));

    // Éditeurs BD franco-belge (Dargaud, Dupuis, Lombard, Casterman, Soleil…)
    // → toujours BD, jamais Comics US — même si les subjects disent « graphic novels ».
    if (bdPublisher) return BookSubcategory.bd;
    if (francoBdAuthor) return BookSubcategory.bd;
    if (looksBdSubj) return BookSubcategory.bd;
    if (mixedPublisher && !looksComicsSubj) return BookSubcategory.bd;

    // Comics US ensuite.
    if (comicsPublisher) return BookSubcategory.comics;
    if (usComicsAuthor) return BookSubcategory.comics;
    if (mixedPublisher && looksComicsSubj) return BookSubcategory.comics;
    if (looksComicsSubj) return BookSubcategory.comics;
    if (blob.contains('bande dessinée') ||
        blob.contains('bande dessinee') ||
        RegExp(r'\bbd\b').hasMatch(blob)) {
      return BookSubcategory.bd;
    }

    const novelHints = [
      'fiction',
      'roman',
      'novel',
      'literature',
      'fantasy',
      'litrpg',
      'lit-rpg',
      'thriller',
      'romance',
      'science fiction',
      'sci-fi',
      'science-fiction',
      'mystery',
      'horror',
      'young adult',
      'historical fiction',
    ];
    if (novelHints.any((h) => subj.contains(h) || blob.contains(h))) {
      return BookSubcategory.novel;
    }
    // Ni Manga / BD / Comics → Roman (évite le badge « Autre »).
    return BookSubcategory.novel;
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

  static ParsedBookTitle parse(
    String title, {
    int? apiVolumeNumber,
    String? queryHint,
  }) =>
      BookTitleParser.parse(
        title,
        apiVolumeNumber: apiVolumeNumber,
        queryHint: queryHint,
      );

  static String normalizeKey(String name) {
    var s = name.toLowerCase().trim();
    s = s
        .replaceAll(RegExp(r'[–—−]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^the\s+'), '')
        .replaceAll(RegExp(r'^les?\s+'), '');
    return s;
  }

  /// Le texte (description, collection, sous-titre) cite le nom de la série.
  static bool textMentionsSeries(String text, String seriesName) {
    final want = _foldAccents(normalizeKey(seriesName));
    if (want.length < 3) return false;
    return _foldAccents(normalizeKey(text)).contains(want);
  }

  /// Premier nom avant « & », « , » ou « et » (« Lucinda Riley & … » → Riley).
  static String? leadAuthorName(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.length < 3) return null;
    final cut = s.split(RegExp(r'\s*(?:&|,| et )\s*')).first.trim();
    return cut.length >= 3 ? cut : null;
  }

  /// Le titre partage un mot de la requête (« sœur » ↔ « sœurs »).
  static bool titleSharesQueryWord(String query, String title) {
    final blob = _foldAccents(normalizeKey(title));
    for (final w in queryWords(query)) {
      if (w.length < 4) continue;
      if (blob.contains(w)) return true;
      if (w.endsWith('s') && blob.contains(w.substring(0, w.length - 1))) {
        return true;
      }
    }
    return false;
  }

  /// Clé stricte d'identité (égalité seule : pas de préfixe, pas de contains).
  static String normalizeSeriesKey(String name) => mergeKey(name);

  /// Vrai seulement si les deux noms sont la même série.
  /// « Jujutsu Kaisen », « Jujutsu Kaisen 0 » et « Jujutsu Kaisen Modulo »
  /// sont trois séries distinctes.
  static bool namesMatch(String a, String b) =>
      normalizeSeriesKey(a) == normalizeSeriesKey(b);

  static const _queryStopWords = {
    'le',
    'la',
    'les',
    'de',
    'du',
    'des',
    'un',
    'une',
    'the',
    'of',
    'et',
    'and',
    'au',
    'aux',
    'en',
  };

  static String _foldAccents(String raw) {
    return raw
        .replaceAll('œ', 'oe')
        .replaceAll('æ', 'ae')
        .replaceAll(RegExp('[àâä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[ïî]'), 'i')
        .replaceAll(RegExp('[ôö]'), 'o')
        .replaceAll(RegExp('[ùûü]'), 'u')
        .replaceAll('ç', 'c');
  }

  /// Mots significatifs d'une requête utilisateur.
  static List<String> queryWords(String query) {
    final folded = _foldAccents(normalizeKey(query));
    return folded
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3 && !_queryStopWords.contains(w))
        .toList();
  }

  /// La requête de l'utilisateur : chaque mot est dans le titre, le sous-titre
  /// ou le nom de collection. Pas la description. L'égalité stricte reste
  /// réservée à [namesMatch] / `isOwnedSeries`.
  static bool queryWordsMatchIdentity({
    required String query,
    required String title,
    String? subtitle,
    String? collectionName,
    String? seriesTitle,
  }) {
    final words = queryWords(query);
    if (words.isEmpty) return true;
    final blob = _foldAccents(
      normalizeKey(
        '$title ${subtitle ?? ''} ${collectionName ?? ''} ${seriesTitle ?? ''}',
      ),
    );
    if (words.every(blob.contains)) return true;
    final key = _foldAccents(normalizeKey(query));
    if (key == 'sorceleur' || key == 'witcher') {
      return blob.contains('sorceleur') || blob.contains('witcher');
    }
    return false;
  }

  /// Requêtes Apple Books FR supplémentaires pour les titres nommés par l'utilisateur.
  static List<String> extraItunesQueries(String query) {
    final key = _foldAccents(normalizeKey(query));
    if (key == 'sorceleur' || key == 'witcher') {
      return const ['Sorceleur Andrzej Sapkowski', 'The Witcher'];
    }
    if (key == 'harry potter' || key.startsWith('harry potter ')) {
      return const ['Harry Potter Rowling'];
    }
    if (key == 'monster') return const ['Monster Naoki Urasawa'];
    if (key == 'one piece') return const ['One Piece Glénat'];
    return const [];
  }

  /// Même auteur, et la description cite la série avec un numéro de tome.
  /// Un titre qui porte déjà un autre nom de série (« Trilogie Hussite ») est ignoré.
  static bool descriptionBindsToSeries({
    required String? author,
    required String? expectedAuthor,
    required String title,
    required String description,
    required String seriesName,
  }) {
    final expected = expectedAuthor?.trim() ?? '';
    if (expected.isEmpty) return false;
    if (!authorsMatch(author, expected)) return false;
    final desc = description.trim();
    if (!textMentionsSeries(desc, seriesName)) return false;
    if (BookTitleParser.extractVolumeFromProse(desc) == null) return false;
    final explicit = BookTitleParser.extractVolumeNumberStrict(title);
    if (explicit != null) {
      final parsed = parse(title);
      if (parsed.hasSeries &&
          !namesMatch(parsed.seriesName!, seriesName) &&
          !textMentionsSeries(title, seriesName)) {
        return false;
      }
    }
    return true;
  }

  /// Le titre, le sous-titre ou le `collectionName` Apple désigne cette série.
  /// La description n'est jamais lue ici.
  static bool catalogIdentityMatchesSeries({
    required String title,
    String? subtitle,
    String? collectionName,
    String? seriesTitle,
    required String seriesName,
  }) {
    final want = seriesName.trim();
    if (want.length < 2) return false;
    if (hitBelongsToSeries(title, want)) return true;
    if (normalizeSeriesKey(title) == normalizeSeriesKey(want)) return true;
    final sub = subtitle?.trim() ?? '';
    if (sub.isNotEmpty &&
        (hitBelongsToSeries(sub, want) ||
            normalizeSeriesKey(sub) == normalizeSeriesKey(want))) {
      return true;
    }
    for (final extra in [collectionName, seriesTitle]) {
      final c = extra?.trim() ?? '';
      if (c.isEmpty) continue;
      if (hitBelongsToSeries(c, want)) return true;
      if (normalizeSeriesKey(c) == normalizeSeriesKey(want)) return true;
      if (textMentionsSeries(c, want)) return true;
    }
    return false;
  }

  /// Vrai si le titre du hit appartient strictement à la série [seriesName].
  /// Une « Intégrale » numérotée n'appartient pas à la série standard.
  static bool hitBelongsToSeries(String hitTitle, String seriesName) {
    final wantRaw = stripOrphanVolumeSuffix(seriesName);
    final parsed = parse(hitTitle, queryHint: seriesName);
    final extractedRaw = parsed.hasSeries
        ? parsed.seriesName!.trim()
        : (BookTitleParser.inferSeriesName(hitTitle, queryHint: seriesName) ??
            stripOrphanVolumeSuffix(hitTitle));
    final wantIntegrale = BookTitleParser.looksLikeIntegraleEdition(wantRaw);
    final gotIntegrale =
        BookTitleParser.looksLikeIntegraleEdition(extractedRaw);
    if (wantIntegrale != gotIntegrale) return false;
    final want = normalizeKey(stripEditionSuffix(wantRaw));
    if (want.isEmpty) return false;
    final extracted = normalizeKey(stripEditionSuffix(extractedRaw));
    if (extracted.isEmpty) return false;
    return extracted == want;
  }

  /// Titre qui ressemble à un chapitre / scan unitaire (pas un tome relié).
  static bool looksLikeChapterOrScan(String title) {
    final t = title.toLowerCase();
    if (RegExp(
      r'\b(?:chapitre|chapter|chap\.?|ch\.?|épisode|episode|ep\.)\s*\d+',
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

  /// « One Piece Doors », « Sur les mers de One Piece », « Dofus Monster ».
  /// Le nom parsé contient toute la série, plus d'autres mots : c'est une autre
  /// œuvre. « One Piece - Édition originale » reste One Piece.
  static bool isSpinOffSeriesName(String extracted, String want) {
    final extractedClean =
        stripEditionSuffix(stripOrphanVolumeSuffix(extracted));
    final wantClean = stripEditionSuffix(stripOrphanVolumeSuffix(want));
    if (namesMatch(extractedClean, wantClean)) return false;
    final wantWords = queryWords(wantClean);
    final gotWords = queryWords(extractedClean);
    if (wantWords.isEmpty || gotWords.length <= wantWords.length) {
      return false;
    }
    final got = gotWords.toSet();
    return wantWords.every(got.contains);
  }

  /// Manga : l'auteur doit coller quand on le connaît (Monster ≠ Michael Grant).
  /// BD : un changement de scénariste reste accepté si le titre est la série.
  /// Un spin-off est toujours rejeté, quelle que soit la catégorie.
  static bool rejectAsDifferentWork({
    required String title,
    required String seriesName,
    required String? author,
    required String? expectedAuthor,
    required bool mangaAuthorRequired,
  }) {
    final own = parse(title, queryHint: seriesName).seriesName;
    if (own != null &&
        own.isNotEmpty &&
        isSpinOffSeriesName(own, seriesName)) {
      return true;
    }
    if (BookTitleParser.looksLikeIntegraleEdition(title) &&
        !BookTitleParser.looksLikeIntegraleEdition(seriesName)) {
      return true;
    }
    if (RegExp(
      r'\btomes?\s*\d+\s*(?:à|a|-|–)\s*',
      caseSensitive: false,
    ).hasMatch(title)) {
      return true;
    }
    if (mangaAuthorRequired &&
        !authorMatchesExpected(author, expectedAuthor)) {
      return true;
    }
    return false;
  }

  static String seriesAuthorKey(String seriesName, String? author) {
    final s = mergeKey(seriesName);
    final a = normalizeAuthorKey(author ?? '');
    return a.isEmpty ? s : '$s|$a';
  }

  /// Clé de regroupement bannières : (série normalisée, sous-catégorie).
  /// Sépare Kingdom Manga vs Kingdom Roman sans fragmenter Boruto par auteur.
  static String seriesSubcategoryKey(
    String seriesName,
    BookSubcategory? subcategory,
  ) {
    final s = mergeKey(seriesName);
    final sub = subcategory?.dbValue ?? 'any';
    return '$s|$sub';
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
    var s = name.trim().replaceAll(RegExp(r'[–—−‐‑‒]'), '-');
    // Normalise accents pour matcher « Édition » / « edition ».
    final lower = s.toLowerCase();
    final editionMatch = RegExp(
      r'\s*-?\s*(édition|edition)\s+'
      r'(originale|original|collector|spéciale|speciale|intégrale|integrale)\b.*$',
      caseSensitive: false,
    ).firstMatch(lower);
    if (editionMatch != null) {
      s = s.substring(0, editionMatch.start);
    } else {
      final anyEd = RegExp(
        r'\s*-?\s*(édition|edition)\s+\S+.*$',
        caseSensitive: false,
      ).firstMatch(lower);
      if (anyEd != null) {
        s = s.substring(0, anyEd.start);
      }
    }
    // Ne PAS retirer « Intégrale / Omnibus / Coffret » : c'est une série distincte
    // (« Walking Dead - Intégrale - Tome 25 » ≠ « Walking Dead »).
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
