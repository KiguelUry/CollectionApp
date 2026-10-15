import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/models/collection_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionItem _game(String id, {int sessions = 0, int? gamesPlayed}) =>
    CollectionItem(
      id: id,
      title: 'Jeu $id',
      category: CollectionCategory.boardgame,
      isWishlist: false,
      gamesPlayed: gamesPlayed,
      metadata: {
        'boardgame_plays': [
          for (var i = 0; i < sessions; i++)
            {
              'date': '2026-01-0${i + 1}',
              'players': ['A'],
            },
        ],
      },
    );

void main() {
  final items = [
    _game('a', sessions: 2),
    _game('b'),
    _game('c', gamesPlayed: 3),
    _game('d', gamesPlayed: 0),
  ];

  test('playCountOf : sessions détaillées sinon compteur manuel', () {
    expect(CollectionListFilters.playCountOf(items[0]), 2);
    expect(CollectionListFilters.playCountOf(items[1]), 0);
    expect(CollectionListFilters.playCountOf(items[2]), 3);
  });

  test('unplayedOnly ne garde que les jeux à 0 partie', () {
    final filters = CollectionListFilters(unplayedOnly: true);
    expect(filters.apply(items).map((i) => i.id).toList(), ['b', 'd']);
  });

  test('unplayedOnly compte comme filtre actif', () {
    expect(CollectionListFilters().hasActiveFilterCriteria, isFalse);
    expect(
      CollectionListFilters().copyWith(unplayedOnly: true).hasActiveFilterCriteria,
      isTrue,
    );
  });

  test('copyWith conserve unplayedOnly', () {
    final f = CollectionListFilters(unplayedOnly: true).copyWith(searchQuery: 'x');
    expect(f.unplayedOnly, isTrue);
  });
}
