import 'dart:math';

import '../models/boardgame_play_session.dart';
import '../models/collection_item.dart';

String newPlayShareId({Random? random, DateTime? now}) {
  final r = random ?? Random.secure();
  final ts = (now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36);
  final salt = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  return 'ps_${ts}_$salt';
}

String playShareDedupeKey(String shareId) => 'play:$shareId';

/// Contenu de la notification « partie partagée ».
/// Les pseudos qui désignent l'expéditeur ([senderAliases]) sont remplacés
/// par son nom de compte pour que l'ami le reconnaisse.
Map<String, dynamic> buildPlaySharePayload({
  required BoardgamePlaySession session,
  required String shareId,
  required String gameTitle,
  required String senderUsername,
  required String recipientPlayerName,
  Iterable<String> senderAliases = const [],
  String? bggId,
  String? imageUrl,
}) {
  final map = <String, String>{
    for (final a in senderAliases)
      if (a.trim().isNotEmpty) a.trim().toLowerCase(): senderUsername,
  };
  final shared = session.remapPlayerNames(map).copyWith(shareId: shareId);
  return {
    'share_id': shareId,
    'game_title': gameTitle,
    if (bggId != null && bggId.isNotEmpty) 'bgg_id': bggId,
    if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
    'sender_username': senderUsername,
    'as_player': recipientPlayerName,
    'session': shared.toJson(),
  };
}

/// Session à importer chez le destinataire : son pseudo dans la partie
/// (`as_player`) devient [myDisplayName] s'il est connu.
BoardgamePlaySession? sessionFromSharePayload(
  Map<String, dynamic> payload, {
  String? myDisplayName,
}) {
  final raw = payload['session'];
  if (raw is! Map) return null;
  var session = BoardgamePlaySession.fromJson(Map<String, dynamic>.from(raw));
  final shareId = payload['share_id']?.toString();
  if (session.shareId == null && shareId != null && shareId.isNotEmpty) {
    session = session.copyWith(shareId: shareId);
  }
  final asPlayer = payload['as_player']?.toString().trim();
  final me = myDisplayName?.trim();
  if (asPlayer != null &&
      asPlayer.isNotEmpty &&
      me != null &&
      me.isNotEmpty &&
      asPlayer.toLowerCase() != me.toLowerCase()) {
    session = session.remapPlayerNames({asPlayer.toLowerCase(): me});
  }
  return session;
}

String _playersKey(BoardgamePlaySession s) {
  final names =
      s.players
          .map((p) => p.trim().toLowerCase())
          .where((p) => p.isNotEmpty)
          .toList()
        ..sort();
  return names.join('|');
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Vrai si [incoming] est déjà dans [existing] : même identifiant de partage,
/// ou même jour + mêmes joueurs + même gagnant (saisie manuelle en double).
bool isDuplicatePlay(
  Iterable<BoardgamePlaySession> existing,
  BoardgamePlaySession incoming,
) {
  final shareId = incoming.shareId;
  final key = _playersKey(incoming);
  final winner = incoming.effectiveWinner?.trim().toLowerCase() ?? '';
  for (final s in existing) {
    if (shareId != null && s.shareId == shareId) return true;
    if (!_sameDay(s.date, incoming.date)) continue;
    if (key.isEmpty || _playersKey(s) != key) continue;
    if ((s.effectiveWinner?.trim().toLowerCase() ?? '') == winner) return true;
  }
  return false;
}

/// Jeu de la collection où ranger la partie reçue : BGG id, sinon titre.
CollectionItem? matchSharedPlayItem(
  Iterable<CollectionItem> items, {
  required String gameTitle,
  String? bggId,
}) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (bggId != null && bggId.isNotEmpty) {
    for (final i in items) {
      if (i.metadata?['bgg_id']?.toString() == bggId) return i;
    }
  }
  final t = norm(gameTitle);
  if (t.isEmpty) return null;
  for (final i in items) {
    if (norm(i.title) == t) return i;
  }
  return null;
}
