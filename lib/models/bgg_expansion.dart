/// Extension BGG rattachée à un jeu de base.
class BggExpansion {
  final String bggId;
  final String title;
  final String? imageUrl;
  final int? year;
  final String? summary;
  /// Classement BGG « boardgame » (plus petit = plus populaire).
  final int? bggRank;

  const BggExpansion({
    required this.bggId,
    required this.title,
    this.imageUrl,
    this.year,
    this.summary,
    this.bggRank,
  });
}
