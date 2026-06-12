import 'package:flutter/foundation.dart';

import '../config/app_env.dart';

const _proxiedHosts = {
  'cf.geekdo-images.com',
  'boardgamegeek.com',
  'covers.openlibrary.org',
  'assets.tcgdex.net',
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
};

/// Sur le web, route les couvertures externes via l'Edge Function Supabase (CORS).
String coverUrlForWeb(String url) {
  if (!kIsWeb) return url;

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  if (!_proxiedHosts.contains(uri.host.toLowerCase())) return url;

  final base = AppEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base/functions/v1/image-proxy?url=${Uri.encodeComponent(url)}';
}
