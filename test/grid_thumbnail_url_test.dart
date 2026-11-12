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

    test('Discogs / Apple / Google Books : wsrv.nl', () {
      expect(
        Uri.parse(proxyImageUrl('https://i.discogs.com/abc/image.jpg')).host,
        'wsrv.nl',
      );
      final apple = Uri.parse(
        proxyImageUrl(
          'https://is1-ssl.mzstatic.com/image/thumb/Publication/600x600bb.jpg',
          width: 400,
        ),
      );
      expect(apple.host, 'wsrv.nl');
      expect(apple.queryParameters['w'], '300'); // plafonné
      expect(apple.queryParameters['url'], contains('300x300bb'));
      expect(apple.queryParameters['url'], isNot(contains('600x600bb')));

      final google = Uri.parse(
        proxyImageUrl(
          'http://books.google.com/books/content?id=1&edge=curl&printsec=frontcover',
        ),
      );
      expect(google.host, 'wsrv.nl');
      expect(google.queryParameters['url'], startsWith('https://'));
      expect(google.queryParameters['url'], isNot(contains('edge=curl')));
    });

    test('Yu-Gi-Oh / One Piece : wsrv.nl (pas le CDN brut)', () {
      expect(
        Uri.parse(
          proxyImageUrl('https://images.ygoprodeck.com/images/cards/1.jpg'),
        ).host,
        'wsrv.nl',
      );
      expect(
        Uri.parse(
          proxyImageUrl('https://www.optcgapi.com/media/static/Card_Images/a.jpg'),
        ).host,
        'wsrv.nl',
      );
    });

    test('file:/// et chemins vides ne partent pas sur le réseau', () {
      expect(proxyImageUrl('file:///'), '');
      expect(proxyImageUrl('file:///C:/image.jpg'), '');
      expect(proxyImageUrl(''), '');
      expect(proxyImageUrl('c0edef9a-sans-hote'), '');
    });

    test('Open Library / AniList / TMDB : HTTPS direct (pas wsrv)', () {
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
        Uri.parse(proxyImageUrl('https://image.tmdb.org/t/p/w500/x.jpg')).host,
        'image.tmdb.org',
      );
    });

    test('MangaDex : append officiel .jpg.256.jpg (jamais replace .256.jpg)', () {
      const src =
          'https://uploads.mangadex.org/covers/aaa/bbb.jpg';
      final out = mangaDexThumbnailUrl(src, width: 360);
      // Docs MangaDex : append, pas replace → .../bbb.jpg.256.jpg
      expect(out, endsWith('bbb.jpg.256.jpg'));
      expect(out, isNot(contains('bbb.256.jpg')));
      expect(out, isNot(contains('wsrv.nl')));

      // PNG brut → png.256.jpg
      expect(
        mangaDexThumbnailUrl(
          'https://uploads.mangadex.org/covers/aaa/ccc.png',
          width: 260,
        ),
        endsWith('ccc.png.256.jpg'),
      );

      // Déjà suffixé → renormalisé en .256
      expect(
        mangaDexThumbnailUrl(
          'https://uploads.mangadex.org/covers/aaa/bbb.jpg.512.jpg',
          width: 260,
        ),
        endsWith('bbb.jpg.256.jpg'),
      );

      // Lightbox seul (≥900) → .512.jpg
      expect(
        mangaDexThumbnailUrl(src, width: 1000),
        endsWith('bbb.jpg.512.jpg'),
      );

      final routed = proxyImageUrl(src, width: 360);
      expect(routed, isNot(contains('wsrv.nl')));
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
