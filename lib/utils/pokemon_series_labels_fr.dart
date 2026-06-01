/// Libellés FR pour les blocs Pokémon (API en anglais).
abstract final class PokemonSeriesLabelsFr {
  static const _map = {
    'Mega Evolution': 'Méga-Évolution',
    'Scarlet & Violet': 'Écarlate et Violet',
    'Sword & Shield': 'Épée et Bouclier',
    'Sun & Moon': 'Soleil et Lune',
    'XY': 'XY',
    'Black & White': 'Noir et Blanc',
    'HeartGold & SoulSilver': 'HeartGold SoulSilver',
    'Platinum': 'Platine',
    'Diamond & Pearl': 'Diamant et Perle',
    'EX': 'EX',
    'e-Card': 'e-Card',
    'Neo': 'Neo',
    'Gym': 'Gym',
    'Base': 'Base',
    'Other': 'Autre',
  };

  static String label(String apiSeries) {
    if (_map.containsKey(apiSeries)) return _map[apiSeries]!;
    for (final e in _map.entries) {
      if (apiSeries.toLowerCase().contains(e.key.toLowerCase())) {
        return e.value;
      }
    }
    return apiSeries;
  }

  /// Ordre d’affichage des blocs (récent → ancien).
  static int sortIndex(String apiSeries) {
    final keys = _map.keys.toList();
    final i = keys.indexWhere(
      (k) => apiSeries.toLowerCase().contains(k.toLowerCase()),
    );
    return i >= 0 ? i : keys.length;
  }
}
