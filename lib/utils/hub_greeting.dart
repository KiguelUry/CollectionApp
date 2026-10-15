import 'dart:math';

import '../models/collection_category.dart';

/// Titres généraux (tirage 20 %).
const kGeneralGreetingTitles = <String>[
  'Aventurier',
  'Grand Archiviste',
  'Chineur d\'Élite',
  'Oracle de la Wishlist',
  'Gardien du Trésor',
  'Maître des Étagères',
  'Conservateur Suprême',
  'Chasseur de Reliques',
  'Baron du Stock',
  'Dompteur de Piles',
  'Architecte du Rangement',
  'Seigneur de l\'Inventaire',
  'Détective de l\'Occasion',
  'Empereur des Vitrines',
  'Légende du Butin',
];

/// Surnoms par catégorie active (tirage 60 %, pondéré par le nombre d'objets).
const kCategoryGreetingTitles = <CollectionCategory, List<String>>{
  CollectionCategory.boardgame: [
    'Maître du Jeu',
    'Baron du Meeple',
    'Gardien des Règles',
    'Stratège Suprême',
    'Seigneur des Dés',
    'Roi de la Défausse',
    'Chevalier du Plateau',
    'Bourreau des Scores',
    'Légende du Carton',
    'Dresseur de Tuiles',
    'Architecte du Plateau',
    'Dompteur de Meeples',
    'Grand Maître du Tour par Tour',
    'Oracle des Extensions',
    'Tyran de la Table',
  ],
  CollectionCategory.book: [
    'Dévoreur de Pages',
    'Gardien des Grimoires',
    'Rat de Bibliothèque',
    'Seigneur des Tomes',
    'Maître du Marque-Page',
    'Archiviste des Bulles',
    'Chasseur de Premières Éditions',
    'Samouraï du Manga',
    'Empereur du Papier',
    'Dompteur de Pile à Lire',
    'Alchimiste de l\'Encre',
    'Chevalier du Roman',
    'Baron de la BD',
    'Sage des Étagères',
    'Légende du Relié',
  ],
  CollectionCategory.card: [
    'Sorcier du Deckbuilding',
    'Maître du Foil',
    'Dresseur de Boosters',
    'Seigneur de la Sleeve',
    'Baron du Topdeck',
    'Gardien du Classeur',
    'Chasseur d\'Ultra-Rares',
    'Roi de la Méta',
    'Alchimiste du Mana',
    'Oracle du Tirage',
    'Chevalier du Mint',
    'Légende du Playmat',
    'Empereur de l\'Holographique',
    'Dompteur de Mulligan',
    'Grand Maître du Duel',
  ],
  CollectionCategory.media: [
    'Seigneur du Sillon',
    'Maître du 33 Tours',
    'Alchimiste du Son',
    'Baron de la Platine',
    'Gardien du Diamant',
    'Chasseur de Pressages',
    'Roi du Décibel',
    'Archiviste des Pochettes',
    'Chevalier de l\'Analogique',
    'Oracle du Groove',
    'Dompteur de Galettes',
    'Légende du 180 Grammes',
    'Empereur de la Hi-Fi',
    'Sorcier du Vinyle',
    'Disquaire de l\'Ombre',
  ],
  CollectionCategory.lego: [
    'Architecte en Briques',
    'Maître Constructeur',
    'Seigneur des Tenons',
    'Baron de la Notice',
    'Dompteur de Pièces',
    'Gardien du Set Scellé',
    'Chevalier de l\'ABS',
    'Roi de l\'Assemblage',
    'Ingénieur Miniature',
    'Chasseur de Minifigs',
    'Oracle du Modélisme',
    'Légende de la Brique',
    'Empereur du Diorama',
    'Sorcier de la Pince',
    'Grand Bâtisseur',
  ],
  CollectionCategory.videogame: [
    'Chasseur de Trophées',
    'Légende du Pixel',
    'Seigneur du Framerate',
    'Baron du Pad',
    'Maître du Backlog',
    'Gardien de la Sauvegarde',
    'Chevalier du Boss Final',
    'Roi du Speedrun',
    'Sorcier du Ray-Tracing',
    'Dompteur de Polygones',
    'Archiviste des Cartouches',
    'Empereur du 100%',
    'Oracle du Respawn',
    'Stratège du Clavier-Manette',
    'Héros du New Game+',
  ],
  CollectionCategory.movie: [
    'Cinéphile Suprême',
    'Maître de la Bobine',
    'Seigneur du Blu-Ray',
    'Baron du 7ème Art',
    'Gardien du Steelbook',
    'Roi du Director\'s Cut',
    'Archiviste de la Pellicule',
    'Chevalier du Grand Écran',
    'Chasseur de Coffrets',
    'Oracle du Générique',
    'Dompteur de Séquences',
    'Légende du Home-Cinéma',
    'Empereur de la VOSTFR',
    'Sorcier du Montage',
    'Critique de l\'Ombre',
  ],
};

enum HubGreetingSource { pseudo, general, category }

class HubGreeting {
  final String name;
  final HubGreetingSource source;
  final CollectionCategory? category;

  const HubGreeting({
    required this.name,
    required this.source,
    this.category,
  });

  String get text => 'Salut $name';
}

/// Tirage pondéré : 20 % pseudo, 20 % titre général, 60 % surnom de catégorie
/// (catégorie choisie au prorata des objets possédés dans [counts]).
HubGreeting pickHubGreeting({
  required String username,
  required Map<CollectionCategory, int> counts,
  Set<CollectionCategory>? active,
  Random? random,
}) {
  final rng = random ?? Random();
  final roll = rng.nextDouble();

  if (roll < 0.2) {
    return HubGreeting(name: username, source: HubGreetingSource.pseudo);
  }

  final weighted = <CollectionCategory, int>{
    for (final e in counts.entries)
      if (e.value > 0 &&
          kCategoryGreetingTitles.containsKey(e.key) &&
          (active == null || active.contains(e.key)))
        e.key: e.value,
  };

  if (roll < 0.4 || weighted.isEmpty) {
    return HubGreeting(
      name: kGeneralGreetingTitles[rng.nextInt(kGeneralGreetingTitles.length)],
      source: HubGreetingSource.general,
    );
  }

  final total = weighted.values.fold<int>(0, (a, b) => a + b);
  var target = rng.nextInt(total);
  var chosen = weighted.keys.first;
  for (final e in weighted.entries) {
    if (target < e.value) {
      chosen = e.key;
      break;
    }
    target -= e.value;
  }
  final titles = kCategoryGreetingTitles[chosen]!;
  return HubGreeting(
    name: titles[rng.nextInt(titles.length)],
    source: HubGreetingSource.category,
    category: chosen,
  );
}
