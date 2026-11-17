import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:collection_app/services/community_rules_service.dart';
import 'package:collection_app/utils/cover_image_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveCoverSourceUrl / BGG fit-in', () {
    test('ne mute pas /fit-in/ même en large', () {
      const url =
          'https://cf.geekdo-images.com/abc/fit-in/200x150/pic123.jpg';
      expect(resolveCoverSourceUrl(url, large: true), url);
      expect(resolveCoverSourceUrl(url, large: false), url);
    });

    test('protocole relatif // → https', () {
      expect(
        resolveCoverSourceUrl('//cdn.example.com/a.jpg', large: false),
        'https://cdn.example.com/a.jpg',
      );
    });
  });

  group('CommunityRulesService.gameKeyFor', () {
    test('préfère bgg_id quand présent', () {
      expect(
        CommunityRulesService.gameKeyFor(bggId: '12345', title: 'Zenith'),
        'bgg:12345',
      );
    });

    test('fallback titre normalisé', () {
      expect(
        CommunityRulesService.gameKeyFor(bggId: null, title: '  Zenith  '),
        'title:zenith',
      );
    });
  });

  group('BoardgameScoreTemplate rulesPhrase', () {
    test('joint les règles avec OU', () {
      const t = BoardgameScoreTemplate(
        matchAll: false,
        rules: [
          ScoreRule(target: ScoreRuleTarget.total, op: ScoreRuleOp.gte, value: 5),
          ScoreRule(
            target: ScoreRuleTarget.anyLine,
            op: ScoreRuleOp.gte,
            value: 3,
            link: ScoreRuleJoin.or,
          ),
        ],
      );
      expect(t.rulesPhrase, contains('OU'));
      expect(t.rulesPhrase, contains('Score total ≥ 5'));
    });
  });
}
