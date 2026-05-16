import 'package:flutter/material.dart';

enum CollectionCategory {
  boardgame,
  book,
  watch,
  car,
  videogame,
  movie;

  String get dbValue => name;

  String get label => switch (this) {
        CollectionCategory.boardgame => 'Jeux de société',
        CollectionCategory.book => 'Livres',
        CollectionCategory.watch => 'Montres',
        CollectionCategory.car => 'Voitures',
        CollectionCategory.videogame => 'Jeux vidéo',
        CollectionCategory.movie => 'Films',
      };

  String get description => switch (this) {
        CollectionCategory.boardgame => 'Jeux de plateau & société',
        CollectionCategory.book => 'Manga, BD, romans, essais…',
        CollectionCategory.watch => 'Montres & bracelets',
        CollectionCategory.car => 'Véhicules de collection',
        CollectionCategory.videogame => 'Jeux console & PC',
        CollectionCategory.movie => 'Films & séries',
      };

  IconData get icon => switch (this) {
        CollectionCategory.boardgame => Icons.casino,
        CollectionCategory.book => Icons.menu_book,
        CollectionCategory.watch => Icons.watch,
        CollectionCategory.car => Icons.directions_car,
        CollectionCategory.videogame => Icons.sports_esports,
        CollectionCategory.movie => Icons.movie,
      };

  Color get color => switch (this) {
        CollectionCategory.boardgame => Colors.orange,
        CollectionCategory.book => Colors.indigo,
        CollectionCategory.watch => Colors.blueGrey,
        CollectionCategory.car => Colors.blue,
        CollectionCategory.videogame => Colors.green,
        CollectionCategory.movie => Colors.red,
      };

  bool get supportsBggSearch => this == CollectionCategory.boardgame;

  bool get supportsOpenLibrarySearch => this == CollectionCategory.book;

  static CollectionCategory fromDbValue(String value) {
    // Ancienne catégorie « manga » → regroupée sous Livres
    if (value == 'manga') return CollectionCategory.book;

    return CollectionCategory.values.firstWhere(
      (c) => c.dbValue == value,
      orElse: () => CollectionCategory.boardgame,
    );
  }
}
