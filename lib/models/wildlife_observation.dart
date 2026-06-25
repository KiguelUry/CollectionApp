class WildlifeObservation {
  final String id;
  final String itemId;
  final String userId;
  final DateTime observedAt;
  final String? note;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final String? placeLabel;

  const WildlifeObservation({
    required this.id,
    required this.itemId,
    required this.userId,
    required this.observedAt,
    this.note,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.placeLabel,
  });

  bool get hasLocation => latitude != null && longitude != null;

  /// Titre galerie : « Vu à [Lieu] » ou coordonnées GPS.
  String get seenAtLabel {
    final place = placeLabel?.trim();
    if (place != null && place.isNotEmpty) return 'Vu à $place';
    if (hasLocation) {
      return 'Vu à ${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    }
    return 'Observation';
  }

  factory WildlifeObservation.fromJson(Map<String, dynamic> json) {
    return WildlifeObservation(
      id: json['id'] as String,
      itemId: json['item_id'] as String,
      userId: json['user_id'] as String,
      observedAt: DateTime.parse(json['observed_at'] as String),
      note: json['note'] as String?,
      photoUrl: json['photo_url'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      placeLabel: json['place_label'] as String?,
    );
  }
}
