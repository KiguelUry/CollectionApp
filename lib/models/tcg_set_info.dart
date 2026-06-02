/// Extension / bloc de séries TCG (ex. « Écarlate et Violet », « Platine »).
class TcgSeriesBlock {
  final String id;
  final String name;
  final String? nameFr;
  final String? imageUrl;
  final List<TcgSetInfo> sets;

  const TcgSeriesBlock({
    required this.id,
    required this.name,
    this.nameFr,
    this.imageUrl,
    required this.sets,
  });

  String get displayName => nameFr ?? name;
}

/// Une extension / set (ex. « Foudre Noire » / BLK).
class TcgSetInfo {
  final String id;
  final String name;
  final String? nameFr;
  final String? code;
  final String seriesName;
  final String? imageUrl;
  final String? symbolUrl;
  final String? releaseDate;
  final int? totalCards;

  const TcgSetInfo({
    required this.id,
    required this.name,
    this.nameFr,
    this.code,
    required this.seriesName,
    this.imageUrl,
    this.symbolUrl,
    this.releaseDate,
    this.totalCards,
  });

  String get displayName => nameFr ?? name;

  String get displaySubtitle {
    final parts = <String>[];
    if (code != null && code!.isNotEmpty) parts.add(code!);
    if (totalCards != null) parts.add('$totalCards cartes');
    if (releaseDate != null && releaseDate!.length >= 4) {
      parts.add(releaseDate!.substring(0, 4));
    }
    return parts.join(' · ');
  }
}

/// Carte du catalogue (avant ajout à la collection).
class TcgCatalogCard {
  final String id;
  final String name;
  final String? imageUrl;
  final String? setName;
  final String? number;
  final String? rarity;
  final Map<String, String> raw;

  const TcgCatalogCard({
    required this.id,
    required this.name,
    this.imageUrl,
    this.setName,
    this.number,
    this.rarity,
    this.raw = const {},
  });
}
