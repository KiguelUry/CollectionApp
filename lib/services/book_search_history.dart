import 'package:shared_preferences/shared_preferences.dart';

/// Historique local des recherches livres (SharedPreferences).
abstract final class BookSearchHistory {
  static const _key = 'book_search_recent_queries_v1';
  static const _max = 12;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  static Future<List<String>> add(String query) async {
    final q = query.trim();
    if (q.length < 2) return load();
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    while (list.length > _max) {
      list.removeLast();
    }
    await prefs.setStringList(_key, list);
    return list;
  }

  static Future<List<String>> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == query.toLowerCase());
    await prefs.setStringList(_key, list);
    return list;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
