/// Ami sélectionnable (profil + pseudo + avatar).
class FriendChoice {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;

  const FriendChoice({
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
  });

  factory FriendChoice.fromFriendRow(Map<String, dynamic> row) {
    return FriendChoice(
      profileId: row['profile_id'] as String,
      username: row['username'] as String? ?? 'Ami',
      avatarUrl: row['avatar_url'] as String?,
      accentColor: row['accent_color'] as String?,
    );
  }
}
