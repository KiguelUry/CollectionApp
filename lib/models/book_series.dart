import 'book_subcategory.dart';
import 'novel_rating_matrix.dart';

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

  NovelRatingMatrix get novelMatrix =>
      NovelRatingMatrix.fromMetadata(metadata);

  double? get totalNewValue =>
      _parseDouble(metadata['total_value_new']);

  double? get totalUsedValue =>
      _parseDouble(metadata['total_value_used']);

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
      subcategory: subcategory,
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
}

/// Stats agrégées pour une tuile ou fiche série.
class BookSeriesStats {
  final int ownedCount;
  final int readCount;
  final int wishlistVolumeCount;
  final int totalSlots;
  final double? displayRating;
  final double totalNewValue;
  final double totalUsedValue;

  const BookSeriesStats({
    this.ownedCount = 0,
    this.readCount = 0,
    this.wishlistVolumeCount = 0,
    this.totalSlots = 0,
    this.displayRating,
    this.totalNewValue = 0,
    this.totalUsedValue = 0,
  });

  String get ownedLabel =>
      totalSlots > 0 ? '$ownedCount/$totalSlots' : '$ownedCount';

  String get readLabel =>
      totalSlots > 0 ? '$readCount/$totalSlots' : '$readCount';

  String? get ratingLabel =>
      displayRating != null ? displayRating!.toStringAsFixed(1) : null;
}
