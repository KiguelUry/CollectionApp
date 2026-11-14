import '../services/player_alias_service.dart';

/// Ami sélectionnable (profil + pseudo + avatar).
class FriendChoice {
  final String profileId;
  final String username;
  final String? avatarUrl;
  final String? accentColor;
  /// `greeting_grammar` du profil ami (`feminine` / `masculine` / `neutral`).
  final String? greetingGrammar;

  const FriendChoice({
    required this.profileId,
    required this.username,
    this.avatarUrl,
    this.accentColor,
    this.greetingGrammar,
  });

  PlayerGender get playerGender {
    return switch (greetingGrammar) {
      'feminine' => PlayerGender.feminine,
      'neutral' => PlayerGender.neutral,
      _ => PlayerGender.masculine,
    };
  }

  factory FriendChoice.fromFriendRow(Map<String, dynamic> row) {
    return FriendChoice(
      profileId: row['profile_id'] as String,
      username: row['username'] as String? ?? 'Ami',
      avatarUrl: row['avatar_url'] as String?,
      accentColor: row['accent_color'] as String?,
      greetingGrammar: row['greeting_grammar'] as String?,
    );
  }
}
