/// Extension BGG rattachée à un jeu de base.
class BggExpansion {
  final String bggId;
  final String title;
  final String? imageUrl;
  final int? year;
  final String? summary;

  /// Classement BGG « boardgame » (plus petit = plus populaire).
  final int? bggRank;

  /// Note moyenne BGG /10.
  final double? avgRating;

  const BggExpansion({
    required this.bggId,
    required this.title,
    this.imageUrl,
    this.year,
    this.summary,
    this.bggRank,
    this.avgRating,
  });

  /// Même format que la réponse `expansions` de l'edge function `bgg-api`.
  Map<String, dynamic> toJson() => {
    'bggId': bggId,
    'title': title,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (year != null) 'year': year,
    if (summary != null) 'summary': summary,
    if (bggRank != null) 'bggRank': bggRank,
    if (avgRating != null) 'avgRating': avgRating,
  };

  factory BggExpansion.fromJson(Map<dynamic, dynamic> e) {
    return BggExpansion(
      bggId: e['bggId']?.toString() ?? '',
      title: e['title']?.toString() ?? '',
      imageUrl: e['imageUrl']?.toString(),
      year: e['year'] is int ? e['year'] as int : int.tryParse('${e['year']}'),
      summary: e['summary']?.toString(),
      bggRank: e['bggRank'] is int
          ? e['bggRank'] as int
          : int.tryParse('${e['bggRank']}'),
      avgRating: e['avgRating'] is num
          ? (e['avgRating'] as num).toDouble()
          : double.tryParse('${e['avgRating']}'),
    );
  }
}
