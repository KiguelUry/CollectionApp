/// Nettoyage agressif de `metadata` avant écriture Supabase.
///
/// Règles : jamais de base64 image, jamais de dumps API bruts, pas d'historique
/// marché / listes de boutiques géantes (Egress PostgREST).
Map<String, dynamic> slimMetadata(Map<String, dynamic>? raw) {
  final meta = Map<String, dynamic>.from(raw ?? {});
  if (meta.isEmpty) return meta;

  // Clés interdites / trop lourdes pour être re-SELECT * à chaque ouverture.
  const dropKeys = {
    'volume_covers_json',
    'volume_dates_json',
    'bgg_gallery_urls',
    'stores_prices',
    'market_price_history',
    'raw_api',
    'api_payload',
    'itunes_raw',
    'google_books_raw',
    'mangadex_raw',
    'full_json',
  };
  for (final k in dropKeys) {
    meta.remove(k);
  }

  // Truncate synopsis / description trop longues (garder l'utile UI).
  for (final key in ['bgg_description', 'description', 'synopsis']) {
    final v = meta[key];
    if (v is String && v.length > 4000) {
      meta[key] = '${v.substring(0, 4000)}…';
    }
  }

  // Purge toute valeur data:image base64 (ne doit jamais vivre en DB).
  final toRemove = <String>[];
  for (final e in meta.entries) {
    final v = e.value;
    if (v is String && _isBase64Image(v)) {
      toRemove.add(e.key);
    } else if (v is Map) {
      meta[e.key] = slimMetadata(Map<String, dynamic>.from(v));
    } else if (v is List) {
      meta[e.key] = [
        for (final item in v)
          if (item is String && _isBase64Image(item))
            null
          else if (item is Map)
            slimMetadata(Map<String, dynamic>.from(item))
          else
            item,
      ].whereType<Object?>().where((x) => x != null).toList();
    }
  }
  for (final k in toRemove) {
    meta.remove(k);
  }

  // boardgame_plays : garder les N dernières parties, sans grilles énormes.
  final plays = meta['boardgame_plays'];
  if (plays is List && plays.length > 40) {
    meta['boardgame_plays'] = plays.sublist(plays.length - 40);
  }
  if (plays is List) {
    meta['boardgame_plays'] = [
      for (final p in plays)
        if (p is Map)
          () {
            final m = Map<String, dynamic>.from(p);
            // score_grid peut être énorme → on ne le re-stocke que si petit.
            final grid = m['score_grid'];
            if (grid is List && grid.length > 80) {
              m.remove('score_grid');
            }
            return m;
          }()
        else
          p,
    ];
  }

  return meta;
}

bool _isBase64Image(String v) {
  final s = v.trimLeft();
  if (s.startsWith('data:image/')) return true;
  // Heuristique : très longue chaîne base64 sans URL.
  if (s.length > 8000 &&
      !s.startsWith('http') &&
      RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s.take(200))) {
    return true;
  }
  return false;
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
