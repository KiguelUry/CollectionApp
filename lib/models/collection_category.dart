import 'package:flutter/material.dart';

enum CollectionCategory {
  boardgame,
  manga,
  watch,
  car,
  book,
  videogame,
  movie;

  String get dbValue => name;

  String get label => switch (this) {
        CollectionCategory.boardgame => 'Jeux de société',
        CollectionCategory.manga => 'Mangas',
        CollectionCategory.watch => 'Montres',
        CollectionCategory.car => 'Voitures',
        CollectionCategory.book => 'Livres',
        CollectionCategory.videogame => 'Jeux vidéo',
        CollectionCategory.movie => 'Films',
      };

  IconData get icon => switch (this) {
        CollectionCategory.boardgame => Icons.casino,
        CollectionCategory.manga => Icons.menu_book,
        CollectionCategory.watch => Icons.watch,
        CollectionCategory.car => Icons.directions_car,
        CollectionCategory.book => Icons.book,
        CollectionCategory.videogame => Icons.sports_esports,
        CollectionCategory.movie => Icons.movie,
      };

  Color get color => switch (this) {
        CollectionCategory.boardgame => Colors.orange,
        CollectionCategory.manga => Colors.purple,
        CollectionCategory.watch => Colors.blueGrey,
        CollectionCategory.car => Colors.blue,
        CollectionCategory.book => Colors.indigo,
        CollectionCategory.videogame => Colors.green,
        CollectionCategory.movie => Colors.red,
      };

  bool get supportsBggSearch => this == CollectionCategory.boardgame;

  static CollectionCategory fromDbValue(String value) {
    return CollectionCategory.values.firstWhere(
      (c) => c.dbValue == value,
      orElse: () => CollectionCategory.boardgame,
    );
  }
}
