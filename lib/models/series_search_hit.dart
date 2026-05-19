/// Résultat de recherche « série » (regroupement Open Library).
class SeriesSearchHit {
  final String name;
  final String? coverUrl;
  final int? estimatedVolumes;
  final String? author;

  const SeriesSearchHit({
    required this.name,
    this.coverUrl,
    this.estimatedVolumes,
    this.author,
  });
}
