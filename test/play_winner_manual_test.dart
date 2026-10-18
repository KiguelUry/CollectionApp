import 'package:collection_app/models/boardgame_play_session.dart';
import 'package:collection_app/models/boardgame_score_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inferWinnerManuallyForced : faux si gagnant = score max', () {
    final grid = BoardgameScoreGrid(
      players: ['Kiki', 'Ib'],
      rounds: [
        BoardgameScoreRound(scores: [558, 62]),
      ],
    );
    final session = BoardgamePlaySession(
      date: DateTime(2026, 1, 1),
      players: ['Kiki', 'Ib'],
      winner: 'Kiki',
      scoreGrid: grid,
      trackScores: true,
    );
    expect(BoardgamePlaySession.inferWinnerManuallyForced(session), isFalse);
    expect(session.effectiveWinner, 'Kiki');
  });

  test('forçage explicite conserve le gagnant manuel', () {
    final grid = BoardgameScoreGrid(
      players: ['Kiki', 'Ib'],
      rounds: [
        BoardgameScoreRound(scores: [558, 62]),
      ],
    );
    final session = BoardgamePlaySession(
      date: DateTime(2026, 1, 1),
      players: ['Kiki', 'Ib'],
      winner: 'Ib',
      scoreGrid: grid,
      trackScores: true,
      winnerManuallyForced: true,
    );
    expect(BoardgamePlaySession.inferWinnerManuallyForced(session), isTrue);
    expect(session.effectiveWinner, 'Ib');
  });

  test('effectiveWinner suit la grille si pas de forçage', () {
    final grid = BoardgameScoreGrid(
      players: ['Kiki', 'Ib'],
      rounds: [
        BoardgameScoreRound(scores: [100, 200]),
      ],
    );
    final session = BoardgamePlaySession(
      date: DateTime(2026, 1, 1),
      players: ['Kiki', 'Ib'],
      winner: 'Kiki',
      scoreGrid: grid,
      trackScores: true,
    );
    expect(session.effectiveWinner, 'Ib');
  });
}
