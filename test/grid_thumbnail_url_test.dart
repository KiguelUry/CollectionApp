import 'package:collection_app/services/bgg_catalog_cache.dart';
import 'package:collection_app/utils/cover_image_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gridThumbnailUrl', () {
    test('BGG : passe par wsrv.nl en WebP 260 px', () {
      const src =
          'https://cf.geekdo-images.com/abc/fit-in/500x500/filters:no_upscale()/pic1.jpg';
      final out = gridThumbnailUrl(src);
      final uri = Uri.parse(out);
      expect(uri.host, 'wsrv.nl');
      expect(uri.queryParameters['w'], '260');
      expect(uri.queryParameters['h'], '260');
      expect(uri.queryParameters['output'], 'webp');
      expect(uri.queryParameters['q'], '80');
      expect(uri.queryParameters['fit'], 'inside');
      expect(uri.queryParameters['url'], contains('/fit-in/320x320/'));
    });

    test('crop → fit=cover, taille personnalisée', () {
      final out = gridThumbnailUrl(
        'https://covers.openlibrary.org/b/id/1-M.jpg',
        crop: true,
        size: 450,
      );
      final uri = Uri.parse(out);
      expect(uri.queryParameters['fit'], 'cover');
      expect(uri.queryParameters['w'], '450');
    });

    test('URL protocole-relatif normalisée en https', () {
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

    test('Wikia / Fandom : URL directe, wsrv se fait refuser en 403', () {
      const src =
          'https://static.wikia.nocookie.net/lego/images/4/48/75403_alt1.png/revision/latest';
      expect(gridThumbnailUrl(src), src);
      expect(
        gridThumbnailUrl('https://lego.fandom.com/wiki/Special:FilePath/x.png'),
        'https://lego.fandom.com/wiki/Special:FilePath/x.png',
      );
    });

    test('stockage Supabase public : transformé', () {
      final out = gridThumbnailUrl(
        'https://abc.supabase.co/storage/v1/object/public/covers/a.jpg',
      );
      expect(Uri.parse(out).host, 'wsrv.nl');
    });
  });

  test('clé de recherche partagée normalisée', () {
    expect(
      BggSearchSharedCache.normalizeKey('  smart:Sea   SALT '),
      'smart:sea salt',
    );
  });
}
