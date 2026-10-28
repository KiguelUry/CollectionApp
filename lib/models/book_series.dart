import 'book_subcategory.dart';

class BookSeries {
  final String id;
  final String ownerId;
  final String name;
  final BookSubcategory subcategory;
  final String? coverUrl;
  final String? parentSeriesId;
  final String? description;
  final double? userRating;
  final String? userReview;
  final int? expectedVolumeCount;
  final bool wishlistEntireSeries;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BookSeries({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.subcategory,
    this.coverUrl,
    this.parentSeriesId,
    this.description,
    this.userRating,
    this.userReview,
    this.expectedVolumeCount,
    this.wishlistEntireSeries = false,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  bool get isSubArc => parentSeriesId != null;

  /// One-shot uniquement pour Roman/Autre avec flag explicite et ≤ 1 tome.
  /// Manga / BD / Comics ne sont JAMAIS « Œuvre unique » par défaut.
  bool get isStandalone {
    if (subcategory == BookSubcategory.manga ||
        subcategory == BookSubcategory.bd ||
        subcategory == BookSubcategory.comics) {
      return false;
    }
    if (metadata['is_standalone'] != true) return false;
    final n = expectedVolumeCount;
    return n == null || n <= 1;
  }

  double? get totalNewValue =>
      _parseDouble(metadata['total_value_new']);

  double? get totalUsedValue =>
      _parseDouble(metadata['total_value_used']);

  /// Note communauté /5 (AniList / Google Books / OpenLibrary).
  double? get communityRating {
    final r = _parseDouble(metadata['community_rating']);
    if (r == null || r <= 0) return null;
    return r > 5.0 ? r / 2 : r;
  }

  /// Auteur de la série (stocké dynamiquement dans metadata à l’ajout).
  String? get author {
    final a = metadata['author']?.toString().trim();
    if (a == null || a.isEmpty) return null;
    return a;
  }

  /// Couverture choisie manuellement — l’enrichissement ne doit pas l’écraser.
  bool get coverLocked => metadata['cover_locked'] == true;

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory BookSeries.fromJson(Map<String, dynamic> json) {
    return BookSeries(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      subcategory: BookSubcategory.fromDbValue(json['subcategory'] as String?),
      coverUrl: json['cover_url'] as String?,
      parentSeriesId: json['parent_series_id'] as String?,
      description: json['description'] as String?,
      userRating: _parseDouble(json['user_rating']),
      userReview: json['user_review'] as String?,
      expectedVolumeCount: json['expected_volume_count'] as int?,
      wishlistEntireSeries: json['wishlist_entire_series'] as bool? ?? false,
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const {},
      ),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'owner_id': ownerId,
        'name': name,
        'subcategory': subcategory.dbValue,
        'cover_url': coverUrl,
        'parent_series_id': parentSeriesId,
        'description': description,
        'user_rating': userRating,
        'user_review': userReview,
        'expected_volume_count': expectedVolumeCount,
        'wishlist_entire_series': wishlistEntireSeries,
        'metadata': metadata,
      };

  Map<String, dynamic> toUpdateJson() => {
        'name': name,
        'subcategory': subcategory.dbValue,
        'cover_url': coverUrl,
        'description': description,
        'user_rating': userRating,
        'user_review': userReview,
        'expected_volume_count': expectedVolumeCount,
        'wishlist_entire_series': wishlistEntireSeries,
        'metadata': metadata,
      };

  BookSeries copyWith({
    String? name,
    BookSubcategory? subcategory,
    String? coverUrl,
    String? description,
    double? userRating,
    String? userReview,
    int? expectedVolumeCount,
    bool? wishlistEntireSeries,
    Map<String, dynamic>? metadata,
    bool clearUserRating = false,
  }) {
    return BookSeries(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      subcategory: subcategory ?? this.subcategory,
      coverUrl: coverUrl ?? this.coverUrl,
      parentSeriesId: parentSeriesId,
      description: description ?? this.description,
      userRating: clearUserRating ? null : (userRating ?? this.userRating),
      userReview: userReview ?? this.userReview,
      expectedVolumeCount: expectedVolumeCount ?? this.expectedVolumeCount,
      wishlistEntireSeries: wishlistEntireSeries ?? this.wishlistEntireSeries,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Copie avec auteur persisté dans metadata (sans écraser si [author] vide).
  BookSeries withAuthor(String? author) {
    final a = author?.trim();
    if (a == null || a.isEmpty) return this;
    if (this.author == a) return this;
    final meta = Map<String, dynamic>.from(metadata);
    meta['author'] = a;
    return copyWith(metadata: meta);
  }
}

/// Stats agrégées pour une tuile ou fiche série.
class BookSeriesStats {
  final int ownedCount;
  final int readCount;
  final int wishlistVolumeCount;
  final int totalSlots;
  /// Moyenne des notes personnelles (tomes / série).
  final double? displayRating;
  /// Note communauté /5.
  final double? communityRating;
  final double totalNewValue;
  final double totalUsedValue;

  const BookSeriesStats({
    this.ownedCount = 0,
    this.readCount = 0,
    this.wishlistVolumeCount = 0,
    this.totalSlots = 0,
    this.displayRating,
    this.communityRating,
    this.totalNewValue = 0,
    this.totalUsedValue = 0,
  });

  String get ownedLabel =>
      totalSlots > 0 ? '$ownedCount/$totalSlots' : '$ownedCount';

  /// Lus / total des tomes (lus même sans possession).
  String get readLabel =>
      totalSlots > 0 ? '$readCount/$totalSlots' : '$readCount';

  bool get isComplete =>
      totalSlots > 0 && ownedCount >= totalSlots;

  double get ownedProgress =>
      totalSlots > 0 ? (ownedCount / totalSlots).clamp(0.0, 1.0) : 0;

  String? get ratingLabel {
    final r = displayRating ?? communityRating;
    if (r == null || r < 0) return null;
    final onFive = r > 5.0 ? r / 2 : r;
    if (onFive < 0) return null;
    return '★ ${onFive.toStringAsFixed(1)}';
  }

  String? get valueLabel {
    final v = totalUsedValue > 0 ? totalUsedValue : totalNewValue;
    if (v <= 0) return null;
    return '~${v.round()} €';
  }

  BookSeriesStats copyWith({
    int? ownedCount,
    int? readCount,
    int? wishlistVolumeCount,
    int? totalSlots,
    double? displayRating,
    double? communityRating,
    double? totalNewValue,
    double? totalUsedValue,
    bool clearDisplayRating = false,
  }) {
    return BookSeriesStats(
      ownedCount: ownedCount ?? this.ownedCount,
      readCount: readCount ?? this.readCount,
      wishlistVolumeCount: wishlistVolumeCount ?? this.wishlistVolumeCount,
      totalSlots: totalSlots ?? this.totalSlots,
      displayRating:
          clearDisplayRating ? null : (displayRating ?? this.displayRating),
      communityRating: communityRating ?? this.communityRating,
      totalNewValue: totalNewValue ?? this.totalNewValue,
      totalUsedValue: totalUsedValue ?? this.totalUsedValue,
    );
  }
}
