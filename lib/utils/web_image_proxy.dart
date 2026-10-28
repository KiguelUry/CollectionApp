import 'package:flutter/foundation.dart';

import '../config/app_env.dart';
import '../config/supabase_public_config.dart';

/// Hôtes chargés en direct sur le web (<img> natif, CORS OK — pas le proxy).
const _directWebImageHosts = {
  'cf.geekdo-images.com',
  'boardgamegeek.com',
  'images.ygoprodeck.com',
  'assets.tcgdex.net',
  'cards.lorcast.io',
  'cdn.riftscribe.gg',
  'www.optcgapi.com',
  // AniList CDN : OK en <img>.
  's4.anilist.co',
  'anilist.co',
  // uploads.mangadex.org : JAMAIS en direct (hotlink → bannière blanche).
};

const _proxiedHosts = {
  'covers.openlibrary.org',
  'api.tcgdex.net',
  'images.pokemontcg.io',
  'i.discogs.com',
  'img.discogs.com',
  'st.discogs.com',
  'image.tmdb.org',
  'media.rawg.io',
  'cdn.cloudflare.steamstatic.com',
  'cdn.rebrickable.com',
  'images.brickset.com',
  'm.media-amazon.com',
  'books.google.com',
  'lh3.googleusercontent.com',
  'uploads.mangadex.org',
};

/// Sur le web, route les couvertures externes via l'Edge Function (CORS / anti-hotlink).
String coverUrlForWeb(String url) {
  if (!kIsWeb) {
    // Mobile aussi : MangaDex bloque parfois selon Referer WebView.
    final uri = Uri.tryParse(url);
    if (uri != null &&
        uri.host.toLowerCase() == 'uploads.mangadex.org') {
      return _supabaseImageProxy(url);
    }
    return url;
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  final host = uri.host.toLowerCase();
  if (_directWebImageHosts.contains(host)) return url;
  if (!_proxiedHosts.contains(host)) {
    // MangaDex hors liste explicite → forcer proxy si host mangadex.
    if (host.endsWith('mangadex.org')) return _supabaseImageProxy(url);
    return url;
  }

  return _supabaseImageProxy(url);
}

String _supabaseImageProxy(String url) {
  final base = (AppEnv.supabaseUrl.isNotEmpty
          ? AppEnv.supabaseUrl
          : SupabasePublicConfig.url)
      .replaceAll(RegExp(r'/+$'), '');
  final anon = AppEnv.supabaseAnonKey.trim().isNotEmpty
      ? AppEnv.supabaseAnonKey.trim()
      : SupabasePublicConfig.anonKey;
  final qp = StringBuffer('url=${Uri.encodeComponent(url)}');
  qp.write('&apikey=${Uri.encodeComponent(anon)}');
  // image-proxy (images) ; fallback wsrv si besoin côté caller.
  return '$base/functions/v1/image-proxy?$qp';
}
