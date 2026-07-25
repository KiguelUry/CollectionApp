import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'affichage de la collection jeux de société.
class BoardgameCollectionPreferences {
  BoardgameCollectionPreferences._();
  static final BoardgameCollectionPreferences instance =
      BoardgameCollectionPreferences._();

  static const _keyShowExpansions = 'boardgame_show_owned_expansions_v1';
  static const _keyPreferredLanguages = 'boardgame_preferred_languages_v1';

  bool _showOwnedExpansions = false;
  Set<String> _preferredLanguages = {'fr'};
  bool _loaded = false;

  bool get showOwnedExpansions => _showOwnedExpansions;
  Set<String> get preferredLanguages => Set.unmodifiable(_preferredLanguages);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _showOwnedExpansions = prefs.getBool(_keyShowExpansions) ?? false;
    final langs = prefs.getStringList(_keyPreferredLanguages);
    if (langs != null && langs.isNotEmpty) {
      _preferredLanguages = langs.map((e) => e.toLowerCase()).toSet();
    }
    _loaded = true;
  }

  Future<void> setShowOwnedExpansions(bool value) async {
    await load();
    _showOwnedExpansions = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowExpansions, value);
  }

  Future<void> setPreferredLanguages(Set<String> codes) async {
    await load();
    _preferredLanguages = codes.map((e) => e.toLowerCase()).where((e) => e.isNotEmpty).toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyPreferredLanguages, _preferredLanguages.toList());
  }
}
