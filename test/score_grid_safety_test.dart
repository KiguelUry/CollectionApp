import 'package:collection_app/models/boardgame_play_session.dart';
import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('une ligne trop courte est complétée et le total additionne tout', () {
    final grid = BoardgameScoreGrid.fromJson({
      'players': ['Kiki', 'Mom'],
      'rounds': [
        {'label': 'Mercure', 'scores': [1]},
        {'label': 'Vénus', 'scores': [2, 1]},
        {'label': 'Mars', 'scores': [2, 1], 'malus': true},
        {'label': 'Jupiter', 'scores': [1, 1]},
      ],
    });

    expect(grid.rounds.first.scores, [1, null]);
    expect(grid.columnTotals(), [2, 1]);
    expect(grid.detached().rounds.first.scores, isNot(same(grid.rounds.first.scores)));
  });

  test('le nom du modèle survit à l\'enregistrement', () {
    final session = BoardgamePlaySession(
      date: DateTime(2026, 11, 12),
      players: const ['Kiki', 'Mom'],
      presetName: '2 joueurs',
    );
    final restored = BoardgamePlaySession.fromJson(session.toJson());
    expect(restored.presetName, '2 joueurs');
  });
}
