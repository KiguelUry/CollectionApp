import 'package:collection_app/services/bgg_catalog_cache.dart';
import 'package:collection_app/utils/cover_image_url.dart';
import 'package:collection_app/utils/web_image_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gridThumbnailUrl / proxyImageUrl', () {
    test('BGG : passe par wsrv.nl en WebP', () {
      const src =
          'https://cf.geekdo-images.com/abc/fit-in/500x500/filters:no_upscale()/pic1.jpg';
      final out = gridThumbnailUrl(src);
      final uri = Uri.parse(out);
      expect(uri.host, 'wsrv.nl');
      expect(uri.queryParameters['w'], '260');
      expect(uri.queryParameters['output'], 'webp');
      expect(uri.queryParameters['url'], contains('/fit-in/320x320/'));
    });

    test('Discogs : wsrv.nl', () {
      final out = proxyImageUrl(
        'https://i.discogs.com/abc/image.jpg',
        width: 360,
      );
      expect(Uri.parse(out).host, 'wsrv.nl');
    });

    test('Open Library / AniList / Apple / Google : HTTPS direct (pas wsrv)', () {
      expect(
        Uri.parse(gridThumbnailUrl('https://covers.openlibrary.org/b/id/1-M.jpg'))
            .host,
        'covers.openlibrary.org',
      );
      expect(
        Uri.parse(proxyImageUrl('https://s4.anilist.co/file/anilistcdn/x.jpg'))
            .host,
        's4.anilist.co',
      );
      expect(
        Uri.parse(
          proxyImageUrl(
            'https://is1-ssl.mzstatic.com/image/thumb/100x100bb.jpg',
          ),
        ).path,
        contains('400x400bb'),
      );
      expect(
        Uri.parse(
          proxyImageUrl('http://books.google.com/books/content?id=1'),
        ).scheme,
        'https',
      );
      expect(
        Uri.parse(proxyImageUrl('https://image.tmdb.org/t/p/w500/x.jpg')).host,
        'image.tmdb.org',
      );
    });

    test('MangaDex : jamais wsrv ; miniature .512.jpg', () {
      const src =
          'https://uploads.mangadex.org/covers/aaa/bbb.png.jpg';
      final out = mangaDexThumbnailUrl(src, width: 360);
      expect(out, endsWith('.512.jpg'));
      expect(out, isNot(contains('wsrv.nl')));
      // Hors web (tests) : URL directe miniature, pas catalog-proxy.
      final routed = proxyImageUrl(src, width: 360);
      expect(routed, isNot(contains('wsrv.nl')));
      expect(routed, contains('uploads.mangadex.org'));
      expect(routed, endsWith('.512.jpg'));
    });

    test('URL protocole-relatif BGG normalisée en https via wsrv', () {
      final out = gridThumbnailUrl('//cf.geekdo-images.com/x/pic.png');
      expect(
        Uri.parse(out).queryParameters['url'],
        startsWith('https://cf.geekdo-images.com/'),
      );
    });

    test('non transformables : data, déjà wsrv, stockage privé', () {
      const data = 'data:image/png;base64,AAAA';
      expect(gridThumbnailUrl(data), data);
      const already = 'https://wsrv.nl/?url=x&w=300';
      expect(gridThumbnailUrl(already), already);
      const private =
          'https://abc.supabase.co/storage/v1/object/sign/covers/a.jpg?token=t';
      expect(gridThumbnailUrl(private), private);
    });

    test('Wikia / Fandom : URL directe', () {
      const src =
          'https://static.wikia.nocookie.net/lego/images/4/48/75403_alt1.png/revision/latest';
      expect(gridThumbnailUrl(src), src);
      expect(
        gridThumbnailUrl('https://lego.fandom.com/wiki/Special:FilePath/x.png'),
        'https://lego.fandom.com/wiki/Special:FilePath/x.png',
      );
    });

    test('stockage Supabase public : HTTPS direct (pas wsrv)', () {
      final out = gridThumbnailUrl(
        'https://abc.supabase.co/storage/v1/object/public/covers/a.jpg',
      );
      expect(Uri.parse(out).host, 'abc.supabase.co');
      expect(out, isNot(contains('wsrv.nl')));
    });
  });

  test('clé de recherche partagée normalisée', () {
    expect(
      BggSearchSharedCache.normalizeKey('  smart:Sea   SALT '),
      'smart:sea salt',
    );
  });
}
