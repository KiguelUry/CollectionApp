/// Jeu affiché dans les grilles catalogue BGG (découverte / recherche).
library;
import '../catalog/models/catalog_entry.dart';
import '../services/user_boardgame_collection_service.dart';

class BggCatalogGame implements CatalogEntry {
  final String bggId;
  @override
  final String title;
  @override
  final String? imageUrl;
  final String? year;
  final String? bggRank;
  final String? hotRank;
  /// Sous-titre affiché (année, joueurs, raison sociale…).
  @override
  final String? subtitle;
  final List<String> genres;
  /// Horodatage ms (feed amis) pour tri récent.
  final int? addedAtMs;

  const BggCatalogGame({
    required this.bggId,
    required this.title,
    this.imageUrl,
    this.year,
    this.bggRank,
    this.hotRank,
    this.subtitle,
    this.genres = const [],
    this.addedAtMs,
  });

  @override
  String get catalogKey => UserBoardgameCollectionService.catalogKeyForGame(
        bggId,
        title,
      );

  factory BggCatalogGame.fromBggMap(
    Map<String, String> map, {
    String? subtitle,
    int? addedAtMs,
  }) {
    final id = map['id'] ?? map['bgg_id'] ?? '';
    final year = map['year'] ?? map['year_published'] ?? '';
    final rank = map['bgg_rank'] ?? '';
    final hot = map['hot_rank'] ?? '';
    final avg = map['avg_rating'] ?? '';
    final players = _playersLabel(
      map['min_players'],
      map['max_players'],
    );
    final parts = <String>[
      if (avg.isNotEmpty) '★ $avg',
      if (year.isNotEmpty) year,
      if (players != null) players,
      if (rank.isNotEmpty && rank != '999999') 'BGG #$rank',
      if (hot.isNotEmpty) 'Hot #$hot',
    ];
    return BggCatalogGame(
      bggId: id,
      title: map['title'] ?? '',
      imageUrl: map['image_url'],
      year: year.isEmpty ? null : year,
      bggRank: rank.isEmpty ? null : rank,
      hotRank: hot.isEmpty ? null : hot,
      subtitle: subtitle ?? (parts.isEmpty ? null : parts.join(' · ')),
      addedAtMs: addedAtMs,
    );
  }

  BggCatalogGame copyWith({
    String? subtitle,
    int? addedAtMs,
  }) {
    return BggCatalogGame(
      bggId: bggId,
      title: title,
      imageUrl: imageUrl,
      year: year,
      bggRank: bggRank,
      hotRank: hotRank,
      subtitle: subtitle ?? this.subtitle,
      genres: genres,
      addedAtMs: addedAtMs ?? this.addedAtMs,
    );
  }

  static String? _playersLabel(String? min, String? max) {
    final a = int.tryParse(min ?? '');
    final b = int.tryParse(max ?? '');
    if (a != null && b != null && a == b) return '$a j.';
    if (a != null && b != null) return '$a–$b j.';
    if (a != null) return '$a+ j.';
    if (b != null) return '≤$b j.';
    return null;
  }
}
