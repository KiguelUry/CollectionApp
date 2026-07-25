/// Langues d'édition jeux de société (metadata + préférences utilisateur).
library;

const kBggLanguages = 'bgg_languages';

/// Codes normalisés : fr, en, de, …
const boardgameLanguageOptions = <(String code, String label)>[
  ('fr', 'Français'),
  ('en', 'Anglais'),
  ('de', 'Allemand'),
  ('es', 'Espagnol'),
  ('it', 'Italien'),
  ('nl', 'Néerlandais'),
];

Set<String> boardgameLanguagesFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?[kBggLanguages];
  if (raw is! List) return {};
  return raw
      .map((e) => normalizeBoardgameLanguageCode(e.toString()))
      .where((e) => e.isNotEmpty)
      .toSet();
}

String normalizeBoardgameLanguageCode(String raw) {
  final v = raw.trim().toLowerCase();
  if (v.isEmpty) return '';
  return switch (v) {
    'french' || 'français' || 'fre' || 'fra' => 'fr',
    'english' || 'anglais' || 'eng' => 'en',
    'german' || 'allemand' || 'deu' || 'ger' => 'de',
    'spanish' || 'espagnol' || 'spa' => 'es',
    'italian' || 'italien' || 'ita' => 'it',
    'dutch' || 'néerlandais' || 'nld' || 'dut' => 'nl',
    _ when v.length == 2 => v,
    _ => v,
  };
}

bool itemMatchesBoardgameLanguages(
  Map<String, dynamic>? metadata,
  Set<String> allowedLanguages,
) {
  if (allowedLanguages.isEmpty) return true;
  final langs = boardgameLanguagesFromMetadata(metadata);
  if (langs.isEmpty) return true;
  return langs.any(allowedLanguages.contains);
}

String boardgameLanguageFilterLabel(Set<String> codes) {
  if (codes.isEmpty) return 'Toutes langues';
  final labels = boardgameLanguageOptions
      .where((o) => codes.contains(o.$1))
      .map((o) => o.$2)
      .toList();
  if (labels.isEmpty) return codes.join(', ');
  return labels.join(' + ');
}
