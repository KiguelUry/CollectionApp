import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:collection_app/widgets/score_template_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScoreCategoryChip emoji', () {
    test('détecte un emoji déjà présent dans le nom', () {
      expect(ScoreCategoryChip.nameHasEmoji('Vénus 🟡'), isTrue);
      expect(ScoreCategoryChip.nameHasEmoji('Terre 🌍'), isTrue);
      expect(ScoreCategoryChip.nameHasEmoji('Mercure'), isFalse);
      expect(ScoreCategoryChip.nameHasEmoji('Mars'), isFalse);
    });

    test('emojiFor mappe les planètes connues', () {
      expect(ScoreCategoryChip.emojiFor('Mercure'), '⚫️');
      expect(ScoreCategoryChip.emojiFor('Vénus'), '🟡');
      expect(ScoreCategoryChip.emojiFor('Terre'), '🌍');
      expect(ScoreCategoryChip.emojiFor('Mars'), '🔴');
      expect(ScoreCategoryChip.emojiFor('Jupiter'), '🟤');
    });
  });

  group('buildScoreTemplateDemoScores', () {
    BoardgameScoreTemplate zenith() => BoardgameScoreTemplate(
          lines: const [
            ScoreLineSpec('Mercure ⚫️'),
            ScoreLineSpec('Vénus 🟡'),
            ScoreLineSpec('Terre 🌍'),
            ScoreLineSpec('Mars 🔴'),
            ScoreLineSpec('Jupiter 🟤'),
          ],
          matchAll: false,
          rules: const [
            ScoreRule(
              target: ScoreRuleTarget.total,
              op: ScoreRuleOp.gte,
              value: 5,
              link: null,
            ),
            ScoreRule(
              target: ScoreRuleTarget.anyLine,
              op: ScoreRuleOp.gte,
              value: 3,
              link: ScoreRuleJoin.or,
            ),
            ScoreRule(
              target: ScoreRuleTarget.filledLineCount,
              op: ScoreRuleOp.gte,
              value: 4,
              cellValue: 1,
              link: ScoreRuleJoin.or,
            ),
          ],
        );

    test('remplit une condition par joueur (OU), pas des nombres aléatoires', () {
      final matrix = buildScoreTemplateDemoScores(zenith(), players: 3);
      expect(matrix.length, 5);
      expect(matrix.every((row) => row.length == 3), isTrue);

      // J1 → score total ≥ 5 (sur première ligne)
      expect(matrix[0][0], 5);
      // J2 → au moins 1 catégorie ≥ 3
      expect(matrix[0][1], 3);
      // J3 → au moins 4 catégories ≥ 1
      expect(matrix.map((row) => row[2]).where((v) => v >= 1).length, 4);
    });

    test('sans règles → tout à zéro', () {
      final t = BoardgameScoreTemplate(
        lines: const [ScoreLineSpec('A'), ScoreLineSpec('B')],
      );
      final matrix = buildScoreTemplateDemoScores(t, players: 2);
      expect(matrix, [
        [0, 0],
        [0, 0],
      ]);
    });

    test('NamedScorePreset round-trip conserve règles', () {
      final preset = NamedScorePreset(
        name: '2 Joueurs',
        confrontation: BoardgameConfrontationType.freeForAll,
        template: zenith(),
      );
      final restored = NamedScorePreset.fromJson(preset.toJson());
      expect(restored, isNotNull);
      expect(restored!.name, '2 Joueurs');
      expect(restored.template.rules.length, 3);
      expect(restored.template.lineNames.length, 5);
    });
  });
}
