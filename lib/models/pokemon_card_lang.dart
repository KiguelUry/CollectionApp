/// Langues TCGdex supportées pour Pokémon.
abstract final class PokemonCardLang {
  static const fr = 'fr';
  static const en = 'en';
  static const ja = 'ja';

  static const all = [fr, en, ja];

  static String label(String lang) => switch (lang) {
        fr => 'Français',
        en => 'English',
        ja => '日本語',
        _ => lang.toUpperCase(),
      };

  static String shortLabel(String lang) => switch (lang) {
        fr => 'FR',
        en => 'EN',
        ja => 'JA',
        _ => lang.toUpperCase(),
      };

  /// Clé catalogue unique : une carte JP et sa version FR = deux entrées.
  static String catalogKey(String tcgdexId, {String lang = fr}) => '$lang:$tcgdexId';

  static String catalogKeyFromMetadata(Map<String, dynamic>? meta) {
    final id = meta?['tcgdex_id']?.toString() ??
        meta?['pokemon_tcg_id']?.toString() ??
        '';
    if (id.isEmpty) return '';
    final lang = meta?['card_lang']?.toString() ?? fr;
    return catalogKey(id, lang: lang);
  }
}
