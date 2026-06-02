import 'package:flutter/material.dart';

enum CollectionCategory {
  boardgame,
  book,
  card,
  car,
  stamp,
  coin,
  media,
  lego,
  watch,
  videogame,
  movie,
  custom;

  String get dbValue => name;

  String get label => switch (this) {
        CollectionCategory.boardgame => 'Jeux de société',
        CollectionCategory.book => 'Livres',
        CollectionCategory.card => 'Cartes',
        CollectionCategory.car => 'Voitures',
        CollectionCategory.stamp => 'Timbres',
        CollectionCategory.coin => 'Monnaies',
        CollectionCategory.media => 'Vinyles / CD',
        CollectionCategory.lego => 'Lego & maquettes',
        CollectionCategory.watch => 'Montres',
        CollectionCategory.videogame => 'Jeux vidéo',
        CollectionCategory.movie => 'Films',
        CollectionCategory.custom => 'Collection perso',
      };

  String get description => switch (this) {
        CollectionCategory.boardgame => 'Jeux de plateau & société',
        CollectionCategory.book => 'Manga, BD, romans, essais…',
        CollectionCategory.card => 'Pokémon, Magic, Panini…',
        CollectionCategory.car => 'Kilométrage, entretien, carnet',
        CollectionCategory.stamp => 'Pays, atelier, tirage',
        CollectionCategory.coin => 'Pays, atelier, tirage',
        CollectionCategory.media => 'Vinyle, CD, cassette',
        CollectionCategory.lego => 'Sets, boîte, montage',
        CollectionCategory.watch => 'Montres & bracelets',
        CollectionCategory.videogame => 'Jeux console & PC',
        CollectionCategory.movie => 'Films & séries',
        CollectionCategory.custom => 'Type personnalisé',
      };

  IconData get icon => switch (this) {
        CollectionCategory.boardgame => Icons.casino,
        CollectionCategory.book => Icons.menu_book,
        CollectionCategory.card => Icons.style,
        CollectionCategory.car => Icons.directions_car,
        CollectionCategory.stamp => Icons.local_post_office,
        CollectionCategory.coin => Icons.paid,
        CollectionCategory.media => Icons.album,
        CollectionCategory.lego => Icons.extension,
        CollectionCategory.watch => Icons.watch,
        CollectionCategory.videogame => Icons.sports_esports,
        CollectionCategory.movie => Icons.movie,
        CollectionCategory.custom => Icons.folder_special_outlined,
      };

  Color get color => switch (this) {
        CollectionCategory.boardgame => Colors.orange,
        CollectionCategory.book => Colors.indigo,
        CollectionCategory.card => Colors.deepPurple,
        CollectionCategory.car => Colors.blue,
        CollectionCategory.stamp => Colors.brown,
        CollectionCategory.coin => Colors.amber,
        CollectionCategory.media => Colors.teal,
        CollectionCategory.lego => Colors.red,
        CollectionCategory.watch => Colors.blueGrey,
        CollectionCategory.videogame => Colors.green,
        CollectionCategory.movie => Colors.pink,
        CollectionCategory.custom => Colors.blueGrey,
      };

  bool get supportsBggSearch => this == CollectionCategory.boardgame;

  bool get supportsOpenLibrarySearch => this == CollectionCategory.book;

  bool get usesMetadataForm => switch (this) {
        CollectionCategory.card ||
        CollectionCategory.car ||
        CollectionCategory.stamp ||
        CollectionCategory.coin ||
        CollectionCategory.media ||
        CollectionCategory.lego ||
        CollectionCategory.watch ||
        CollectionCategory.videogame ||
        CollectionCategory.movie =>
          true,
        _ => false,
      };

  static CollectionCategory fromDbValue(String value) {
    if (value == 'manga') return CollectionCategory.book;

    return CollectionCategory.values.firstWhere(
      (c) => c.dbValue == value,
      orElse: () => CollectionCategory.boardgame,
    );
  }

  /// Masquées du menu principal (données existantes conservées en base).
  static const Set<CollectionCategory> hiddenFromMenu = {
    CollectionCategory.car,
    CollectionCategory.stamp,
    CollectionCategory.coin,
    CollectionCategory.custom,
  };

  static List<CollectionCategory> get menuValues =>
      CollectionCategory.values
          .where((c) => !hiddenFromMenu.contains(c))
          .toList();

  /// Libellé court pour les totaux (ex. « 5 jeux », « 1 livre »).
  String countSummary(int total) {
    if (total == 0) return 'Vide';
    final unit = switch (this) {
      CollectionCategory.boardgame => ('jeu', 'jeux'),
      CollectionCategory.book => ('livre', 'livres'),
      CollectionCategory.card => ('carte', 'cartes'),
      CollectionCategory.car => ('voiture', 'voitures'),
      CollectionCategory.stamp => ('timbre', 'timbres'),
      CollectionCategory.coin => ('pièce', 'pièces'),
      CollectionCategory.media => ('album', 'albums'),
      CollectionCategory.lego => ('set', 'sets'),
      CollectionCategory.watch => ('montre', 'montres'),
      CollectionCategory.videogame => ('jeu vidéo', 'jeux vidéo'),
        CollectionCategory.movie => ('film', 'films'),
        CollectionCategory.custom => ('objet', 'objets'),
      };
    if (total == 1) return '1 ${unit.$1}';
    return '$total ${unit.$2}';
  }
}
