/// Matrice de notes type IMDB pour les sagas romans (phase 5).
class NovelRatingMatrix {
  final List<String> seasonLabels;
  final List<String> chapterLabels;
  /// Clé « saisonIndex:chapitreIndex » → note 0–10 ou null.
  final Map<String, double?> scores;

  const NovelRatingMatrix({
    this.seasonLabels = const [],
    this.chapterLabels = const [],
    this.scores = const {},
  });

  static const storageKey = 'novel_matrix';

  factory NovelRatingMatrix.fromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return const NovelRatingMatrix();
    final raw = metadata[storageKey];
    if (raw is! Map) return const NovelRatingMatrix();
    final seasons = (raw['season_labels'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final chapters = (raw['chapter_labels'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final scoresRaw = raw['scores'] as Map<String, dynamic>? ?? {};
    final scores = <String, double?>{};
    for (final e in scoresRaw.entries) {
      final v = e.value;
      if (v == null) {
        scores[e.key] = null;
      } else if (v is num) {
        scores[e.key] = v.toDouble();
      } else {
        scores[e.key] = double.tryParse(v.toString());
      }
    }
    return NovelRatingMatrix(
      seasonLabels: seasons,
      chapterLabels: chapters,
      scores: scores,
    );
  }

  Map<String, dynamic> toMetadataFragment() {
    return {
      storageKey: {
        'season_labels': seasonLabels,
        'chapter_labels': chapterLabels,
        'scores': scores.map((k, v) => MapEntry(k, v)),
      },
    };
  }

  static String cellKey(int seasonIndex, int chapterIndex) =>
      '$seasonIndex:$chapterIndex';

  double? scoreAt(int seasonIndex, int chapterIndex) =>
      scores[cellKey(seasonIndex, chapterIndex)];

  NovelRatingMatrix withScore(int seasonIndex, int chapterIndex, double? value) {
    final key = cellKey(seasonIndex, chapterIndex);
    return NovelRatingMatrix(
      seasonLabels: seasonLabels,
      chapterLabels: chapterLabels,
      scores: {...scores, key: value},
    );
  }

  NovelRatingMatrix withDimensions({
    required List<String> seasons,
    required List<String> chapters,
  }) {
    return NovelRatingMatrix(
      seasonLabels: seasons,
      chapterLabels: chapters,
      scores: scores,
    );
  }

  /// Couleur rouge → vert pour une note 0–10.
  static int scoreColorArgb(double? score) {
    if (score == null) return 0xFF9E9E9E;
    final t = (score / 10).clamp(0.0, 1.0);
    final r = (255 * (1 - t)).round();
    final g = (200 * t).round();
    return 0xFF000000 | (r << 16) | (g << 8) | 40;
  }
}
