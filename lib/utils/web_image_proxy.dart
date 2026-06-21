import 'package:flutter/foundation.dart';

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
};

const _proxiedHosts = {
  'covers.openlibrary.org',
  'api.tcgdex.net',
  'images.pokemontcg.io',
  // BGG : <img> natif (cf. collection_cover_image) — pas le proxy.
  // Lorcast / OPTCG : chargement direct aussi.
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
  if (_directWebImageHosts.contains(uri.host.toLowerCase())) return url;
  if (!_proxiedHosts.contains(uri.host.toLowerCase())) return url;

  final base = SupabasePublicConfig.url.replaceAll(RegExp(r'/+$'), '');
  return '$base/functions/v1/image-proxy?url=${Uri.encodeComponent(url)}';
}
