import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/utils/group_game_night.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionItem _bg({
  required String id,
  required String title,
  int? min,
  int? max,
  int? time,
  int plays = 0,
}) {
  return CollectionItem(
    id: id,
    title: title,
    category: CollectionCategory.boardgame,
    isWishlist: false,
    minPlayers: min,
    maxPlayers: max,
    playingTime: time,
    gamesPlayed: plays,
  );
}

void main() {
  test('pickGamesForGameNight filtre par nombre de joueurs', () {
    final items = [
      _bg(id: '1', title: 'Azul', min: 2, max: 4),
      _bg(id: '2', title: 'Twilight Imperium', min: 3, max: 6),
      _bg(id: '3', title: 'Solo only', min: 1, max: 1),
    ];
    final picks = pickGamesForGameNight(items, playerCount: 4);
    expect(picks.map((p) => p.item.title), isNot(contains('Solo only')));
    expect(picks.map((p) => p.item.title), contains('Azul'));
  });

  test('priorise les jeux peu joués', () {
    final items = [
      _bg(id: '1', title: 'A', min: 2, max: 4, plays: 20),
      _bg(id: '2', title: 'B', min: 2, max: 4, plays: 0),
    ];
    final picks = pickGamesForGameNight(items, playerCount: 3, count: 1);
    expect(picks.single.item.title, 'B');
  });

  test('formatGameNightShareText', () {
    final text = formatGameNightShareText(
      groupName: 'Famille',
      playerCount: 4,
      picks: [
        GameNightPick(_bg(id: '1', title: 'Catan', min: 3, max: 4, time: 90), 100),
      ],
      inviteLink: 'https://example.com/g/1',
    );
    expect(text, contains('Famille'));
    expect(text, contains('4 joueurs'));
    expect(text, contains('Catan'));
    expect(text, contains('https://example.com/g/1'));
  });
}
