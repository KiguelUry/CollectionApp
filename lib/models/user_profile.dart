class UserProfile {
  final String id;
  final String username;
  final String? avatarUrl;
  final String accentColor;
  final String? bio;
  final bool showcasePublic;
  final String? showcaseToken;
  /// Wishlist visible par les amis (défaut : oui).
  final bool shareWishlist;
  final bool hideCollectionFromNonFriends;
  final bool hideCollectionFromFriends;
  /// Jusqu'à 6 objets « trophées » (ordre conservé).
  final List<String> favoriteItemIds;

  const UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.accentColor = '#673AB7',
    this.bio,
    this.showcasePublic = false,
    this.showcaseToken,
    this.shareWishlist = true,
    this.hideCollectionFromNonFriends = true,
    this.hideCollectionFromFriends = false,
    this.favoriteItemIds = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? 'Joueur',
      avatarUrl: json['avatar_url'] as String?,
      accentColor: (json['accent_color'] as String?) ?? '#673AB7',
      bio: json['bio'] as String?,
      showcasePublic: json['showcase_public'] as bool? ?? false,
      showcaseToken: json['showcase_token'] as String?,
      shareWishlist: json['share_wishlist'] as bool? ?? true,
      hideCollectionFromNonFriends:
          json['hide_collection_from_non_friends'] as bool? ?? true,
      hideCollectionFromFriends:
          json['hide_collection_from_friends'] as bool? ?? false,
      favoriteItemIds: _parseFavoriteIds(json['favorite_item_ids']),
    );
  }

  static List<String> _parseFavoriteIds(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).toList();
  }

  String get initial =>
      username.isNotEmpty ? username[0].toUpperCase() : '?';

  Map<String, dynamic> toUpdateJson() {
    return {
      'username': username.trim(),
      'bio': bio?.trim().isEmpty == true ? null : bio?.trim(),
      'accent_color': accentColor,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }

  UserProfile copyWith({
    String? username,
    String? avatarUrl,
    String? accentColor,
    String? bio,
    bool clearAvatar = false,
    bool clearBio = false,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      accentColor: accentColor ?? this.accentColor,
      bio: clearBio ? null : (bio ?? this.bio),
    );
  }
}

/// Couleurs d'accent proposées pour le profil.
const List<String> profileAccentPresets = [
  '#673AB7',
  '#512DA8',
  '#E91E63',
  '#F44336',
  '#FF9800',
  '#4CAF50',
  '#009688',
  '#2196F3',
  '#3F51B5',
  '#795548',
];
