/// URLs d'assets TCGdex (logos séries / extensions).
String? tcgdexAssetUrl(
  dynamic logo, {
  required String kind,
  required String id,
  String lang = 'fr',
}) {
  if (id.isEmpty) return null;
  if (logo is String && logo.isNotEmpty) {
    if (logo.startsWith('http')) {
      return logo.endsWith('/logo') ? '$logo.webp' : logo;
    }
    if (logo.startsWith('/')) {
      final path = logo.endsWith('/logo') ? '$logo.webp' : logo;
      return 'https://assets.tcgdex.net$path';
    }
  }
  if (kind == 'series') {
    return 'https://assets.tcgdex.net/$lang/$id/${id}1/logo.webp';
  }
  final serie = id.replaceAll(RegExp(r'[^a-z].*', caseSensitive: false), '');
  if (serie.isEmpty) return null;
  return 'https://assets.tcgdex.net/$lang/$serie/$id/logo.webp';
}
