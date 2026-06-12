import '../utils/boardgame_display.dart';
import 'collection_category.dart';
import 'book_subcategory.dart';
import 'card_subcategory.dart';
import 'collection_item.dart';

enum CardCondition {
  mint,
  nearMint,
  excellent,
  good,
  played,
  poor;

  String get dbValue => switch (this) {
        CardCondition.mint => 'mint',
        CardCondition.nearMint => 'near_mint',
        CardCondition.excellent => 'excellent',
        CardCondition.good => 'good',
        CardCondition.played => 'played',
        CardCondition.poor => 'poor',
      };

  String get label => switch (this) {
        CardCondition.mint => 'Mint',
        CardCondition.nearMint => 'Near Mint',
        CardCondition.excellent => 'Excellent',
        CardCondition.good => 'Good',
        CardCondition.played => 'Played',
        CardCondition.poor => 'Poor',
      };

  static CardCondition fromDbValue(String? v) {
    if (v == null) return CardCondition.good;
    return CardCondition.values.firstWhere(
      (e) => e.dbValue == v,
      orElse: () => CardCondition.good,
    );
  }
}

enum GradingCompany {
  psa,
  pca,
  bgs,
  other;

  String get dbValue => name;

  String get label => switch (this) {
        GradingCompany.psa => 'PSA',
        GradingCompany.pca => 'PCA',
        GradingCompany.bgs => 'BGS',
        GradingCompany.other => 'Autre',
      };

  static GradingCompany fromDbValue(String? v) {
    if (v == null) return GradingCompany.psa;
    return GradingCompany.values.firstWhere(
      (e) => e.dbValue == v,
      orElse: () => GradingCompany.other,
    );
  }
}

enum MediaFormat {
  vinyl,
  cd,
  cassette;

  String get dbValue => name;

  String get label => switch (this) {
        MediaFormat.vinyl => 'Vinyle',
        MediaFormat.cd => 'CD',
        MediaFormat.cassette => 'Cassette',
      };

  static MediaFormat fromDbValue(String? v) {
    if (v == null) return MediaFormat.vinyl;
    return MediaFormat.values.firstWhere(
      (e) => e.dbValue == v,
      orElse: () => MediaFormat.vinyl,
    );
  }
}

enum PressingType {
  original,
  reissue;

  String get dbValue => name;

  String get label => switch (this) {
        PressingType.original => 'Pressage original',
        PressingType.reissue => 'Réédition',
      };

  static PressingType fromDbValue(String? v) {
    if (v == null) return PressingType.original;
    return PressingType.values.firstWhere(
      (e) => e.dbValue == v,
      orElse: () => PressingType.original,
    );
  }
}

/// Champs spécifiques stockés en JSON (`metadata`) dans Supabase.
class CategoryMetadata {
  static Map<String, dynamic>? parse(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static String? subtitle(CollectionItem item) {
    switch (item.category) {
      case CollectionCategory.boardgame:
        final parts = <String>[];
        final players = formatPlayerCount(item.minPlayers, item.maxPlayers);
        if (players != null) parts.add(players);
        final time = formatPlayingTime(item.playingTime);
        if (time != null) parts.add(time);
        return parts.isEmpty ? null : parts.join(' · ');
      case CollectionCategory.book:
        final author = item.metadata?['author'] as String?;
        if (author != null && author.isNotEmpty) return author;
        if (item.subcategory != null) {
          return BookSubcategory.fromDbValue(item.subcategory).label;
        }
        return null;
      case CollectionCategory.card:
        if (item.subcategory != null) {
          return CardSubcategory.fromDbValue(item.subcategory).label;
        }
        return null;
      case CollectionCategory.car:
        final km = item.metadata?['mileage_km'];
        if (km != null) return '$km km';
        return null;
      case CollectionCategory.media:
        final artist = item.metadata?['artist'] as String?;
        final fmt = item.metadata?['format'];
        final fmtLabel =
            fmt != null ? MediaFormat.fromDbValue(fmt.toString()).label : null;
        if (artist != null && artist.trim().isNotEmpty) {
          if (fmtLabel != null) return '$artist · $fmtLabel';
          return artist;
        }
        return fmtLabel;
      case CollectionCategory.lego:
        final kind = item.metadata?['lego_kind']?.toString();
        if (kind == 'maquette') return 'Maquette';
        final setNum = item.metadata?['set_number']?.toString();
        if (setNum != null && setNum.isNotEmpty) return 'Set $setNum';
        return null;
      case CollectionCategory.watch:
        final brand = item.metadata?['brand']?.toString();
        final model = item.metadata?['model']?.toString();
        if (brand != null && brand.isNotEmpty) {
          if (model != null && model.isNotEmpty) return '$brand · $model';
          return brand;
        }
        return model;
      case CollectionCategory.videogame:
        return item.metadata?['platform']?.toString();
      case CollectionCategory.movie:
        final year = item.metadata?['year']?.toString();
        if (year != null && year.isNotEmpty) return year;
        return 'Blu-ray / DVD';
      case CollectionCategory.custom:
        return item.metadata?['custom_type_name']?.toString();
      default:
        return null;
    }
  }

  static List<MapEntry<String, String>> detailRows(CollectionItem item) {
    final m = item.metadata ?? {};
    final rows = <MapEntry<String, String>>[];

    switch (item.category) {
      case CollectionCategory.boardgame:
        final year = m['year_published'] ?? m['year'];
        if (year != null && year.toString().isNotEmpty) {
          rows.add(MapEntry('Parution', year.toString()));
        }
        final minAge = m['min_age'];
        if (minAge != null) {
          rows.add(MapEntry('Âge', '$minAge+'));
        }
        break;
      case CollectionCategory.book:
        if ((m['author'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Auteur', m['author'].toString()));
        }
        if ((m['year'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Année', m['year'].toString()));
        }
        if (item.subcategory != null) {
          rows.add(MapEntry(
            'Type',
            BookSubcategory.fromDbValue(item.subcategory).label,
          ));
        }
        break;
      case CollectionCategory.card:
        if (item.subcategory != null) {
          rows.add(MapEntry('Univers', CardSubcategory.fromDbValue(item.subcategory).label));
        }
        if (m['condition'] != null) {
          rows.add(MapEntry('État', CardCondition.fromDbValue(m['condition'].toString()).label));
        }
        if (m['is_graded'] == true) {
          final company = GradingCompany.fromDbValue(m['grading_company']?.toString()).label;
          final grade = m['grade']?.toString() ?? '?';
          rows.add(MapEntry('Gradation', '$company — $grade'));
        } else {
          rows.add(const MapEntry('Gradation', 'Non gradée'));
        }
        break;
      case CollectionCategory.car:
        if (m['mileage_km'] != null) {
          rows.add(MapEntry('Kilométrage', '${m['mileage_km']} km'));
        }
        if ((m['maintenance_history'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Entretien', m['maintenance_history'].toString()));
        }
        if ((m['logbook'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Carnet de bord', m['logbook'].toString()));
        }
        break;
      case CollectionCategory.stamp:
      case CollectionCategory.coin:
        if ((m['country'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Pays', m['country'].toString()));
        }
        if ((m['mint'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Atelier de frappe', m['mint'].toString()));
        }
        if ((m['rarity_tirage'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Tirage / rareté', m['rarity_tirage'].toString()));
        }
        break;
      case CollectionCategory.media:
        rows.add(MapEntry('Format', MediaFormat.fromDbValue(m['format']?.toString()).label));
        if ((m['disc_color'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Couleur du disque', m['disc_color'].toString()));
        }
        rows.add(MapEntry(
          'Édition limitée',
          m['limited_edition'] == true ? 'Oui' : 'Non',
        ));
        rows.add(MapEntry(
          'Pressage',
          PressingType.fromDbValue(m['pressing']?.toString()).label,
        ));
        if ((m['barcode'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Code-barres / QR', m['barcode'].toString()));
        }
        break;
      case CollectionCategory.lego:
        if ((m['set_number'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('N° de set', m['set_number'].toString()));
        }
        if (m['piece_count'] != null) {
          rows.add(MapEntry('Pièces', m['piece_count'].toString()));
        }
        rows.add(MapEntry('Monté', m['is_built'] == true ? 'Oui' : 'Non'));
        rows.add(MapEntry('Boîte', m['box_included'] == true ? 'Oui' : 'Non'));
        break;
      case CollectionCategory.watch:
        if ((m['brand'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Marque', m['brand'].toString()));
        }
        if ((m['model'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Modèle', m['model'].toString()));
        }
        if ((m['reference'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Référence', m['reference'].toString()));
        }
        if ((m['year'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Année', m['year'].toString()));
        }
        break;
      case CollectionCategory.videogame:
        if ((m['platform'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Plateforme', m['platform'].toString()));
        }
        if ((m['year'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Année', m['year'].toString()));
        }
        break;
      case CollectionCategory.movie:
        rows.add(const MapEntry('Support', 'Physique (Blu-ray, DVD…)'));
        if ((m['year'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Année', m['year'].toString()));
        }
        if ((m['director'] as String?)?.isNotEmpty == true) {
          rows.add(MapEntry('Réalisateur', m['director'].toString()));
        }
        break;
      default:
        break;
    }
    return rows;
  }
}
