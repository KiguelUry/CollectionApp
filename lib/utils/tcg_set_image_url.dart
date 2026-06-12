import '../models/card_subcategory.dart';
import '../models/tcg_set_info.dart';

/// Normalise les logos TCGdex (souvent sans extension).
String? normalizeTcgSetLogoUrl(String? url) {
  if (url == null) return null;
  final u = url.trim();
  if (u.isEmpty) return null;
  if (u.contains('assets.tcgdex.net') && u.endsWith('/logo')) {
    return '$u.webp';
  }
  return u;
}

/// Préfixe série Pokémon / TCGdex à partir de l'id set (ex. sv03 → sv).
String? inferTcgdexSeriesId(String setId) {
  final m = RegExp(r'^([a-z]+)', caseSensitive: false).firstMatch(setId.trim());
  return m?.group(1);
}

String? tcgdexSetLogoUrl(String setId, {String? seriesId, String lang = 'fr'}) {
  if (setId.isEmpty) return null;
  final serie = seriesId ?? inferTcgdexSeriesId(setId);
  if (serie == null || serie.isEmpty) return null;
  return 'https://assets.tcgdex.net/$lang/$serie/$setId/logo.webp';
}

String? tcgdexSeriesLogoUrl(String seriesId, {String lang = 'fr'}) {
  if (seriesId.isEmpty) return null;
  return 'https://assets.tcgdex.net/$lang/$seriesId/${seriesId}1/logo.webp';
}

String? scryfallSetSvgUrl(String? setCode) {
  final code = setCode?.trim().toLowerCase();
  if (code == null || code.isEmpty) return null;
  return 'https://svgs.scryfall.io/sets/$code.svg';
}

String? onepieceSetLogoUrl(String setId) {
  final id = setId.trim();
  if (id.isEmpty) return null;
  final slug = id.toLowerCase().replaceAll(' ', '-');
  return 'https://en.onepiece-cardgame.com/images/products/$slug/logo.png';
}

/// URLs à essayer dans l'ordre pour afficher un logo de set / bloc.
List<String> tcgSetLogoCandidates({
  required CardSubcategory subcategory,
  String? imageUrl,
  String? setId,
  String? setCode,
  String? seriesId,
}) {
  final out = <String>[];

  void add(String? raw) {
    final n = normalizeTcgSetLogoUrl(raw);
    if (n == null || n.isEmpty || out.contains(n)) return;
    out.add(n);
  }

  add(imageUrl);

  switch (subcategory) {
    case CardSubcategory.pokemon:
      if (setId != null) add(tcgdexSetLogoUrl(setId, seriesId: seriesId));
      if (seriesId != null) add(tcgdexSeriesLogoUrl(seriesId));
    case CardSubcategory.magic:
      add(scryfallSetSvgUrl(setCode ?? setId));
    case CardSubcategory.onepiece:
      if (setId != null) add(onepieceSetLogoUrl(setId));
    case CardSubcategory.lorcana:
      break;
    default:
      break;
  }

  return out;
}

List<String> tcgBlockLogoCandidates({
  required CardSubcategory subcategory,
  required TcgSeriesBlock block,
}) {
  final first = block.sets.isNotEmpty ? block.sets.first : null;
  return tcgSetLogoCandidates(
    subcategory: subcategory,
    imageUrl: block.imageUrl ?? first?.imageUrl,
    setId: first?.id,
    setCode: first?.code,
    seriesId: block.id,
  );
}

/// Date la plus récente d'un bloc (pour tri « nouveautés en haut »).
String blockLatestReleaseDate(TcgSeriesBlock block) {
  var best = '';
  for (final s in block.sets) {
    final d = s.releaseDate?.trim() ?? '';
    if (d.isNotEmpty && d.compareTo(best) > 0) best = d;
  }
  return best;
}

void sortSetsByReleaseNewest(List<TcgSetInfo> sets) {
  sets.sort((a, b) {
    final da = a.releaseDate ?? '';
    final db = b.releaseDate ?? '';
    final c = db.compareTo(da);
    if (c != 0) return c;
    return b.id.compareTo(a.id);
  });
}

void sortBlocksByReleaseNewest(List<TcgSeriesBlock> blocks) {
  blocks.sort((a, b) {
    final da = blockLatestReleaseDate(a);
    final db = blockLatestReleaseDate(b);
    final c = db.compareTo(da);
    if (c != 0) return c;
    return b.id.compareTo(a.id);
  });
}

/// Tri One Piece : OP-12 avant OP-01.
int compareOnepieceSetId(String a, String b) {
  int num(String id) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(id.replaceAll('-', ''));
    return m != null ? int.tryParse(m.group(1)!) ?? 0 : 0;
  }

  final na = num(a);
  final nb = num(b);
  if (na != nb) return nb.compareTo(na);
  return b.toUpperCase().compareTo(a.toUpperCase());
}
