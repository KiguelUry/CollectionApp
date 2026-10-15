import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../models/boardgame_play_session.dart';
import '../models/boardgame_score_grid.dart';
import '../utils/play_share.dart';
import 'collection_refresh.dart';
import 'global_play_history_service.dart';
import 'notification_service.dart';
import 'player_alias_service.dart';
import 'profile_cache_service.dart';

/// Partage des parties avec les amis liés aux pseudos joueurs.
class PlayShareService {
  PlayShareService._();
  static final instance = PlayShareService._();

  /// Notifie chaque ami lié présent dans la partie (une fois par partie).
  /// Retourne le nombre d'amis notifiés.
  Future<int> shareWithLinkedFriends({
    required BoardgamePlaySession session,
    required String gameTitle,
    String? bggId,
    String? imageUrl,
  }) async {
    final shareId = session.shareId;
    if (shareId == null || session.status != BoardgamePlayStatus.finished) {
      return 0;
    }
    final aliases = PlayerAliasService.instance;
    await aliases.ensureLoaded();
    final linked = aliases.linkedFriendsIn(session.players);
    if (linked.isEmpty) return 0;

    final me = aliases.meIdentity;
    final username = ProfileCacheService.instance.profile?.username ?? 'Un ami';
    final myAliases = <String>[...?me?.names, ?me?.displayName];

    var sent = 0;
    for (final friend in linked) {
      try {
        await NotificationService.instance.send(
          recipientId: friend.profileId,
          type: AppNotificationType.playShared,
          dedupeKey: playShareDedupeKey(shareId),
          payload: buildPlaySharePayload(
            session: session,
            shareId: shareId,
            gameTitle: gameTitle,
            senderUsername: username,
            senderAliases: myAliases,
            recipientPlayerName: friend.playerName,
            bggId: bggId,
            imageUrl: imageUrl,
          ),
        );
        sent++;
      } catch (e) {
        if (kDebugMode) debugPrint('Partage partie → ${friend.username}: $e');
      }
    }
    return sent;
  }

  /// Ajoute la partie reçue à l'historique (jeu possédé ou partie orpheline).
  Future<String> importSharedPlay(Map<String, dynamic> payload) async {
    final aliases = PlayerAliasService.instance;
    await aliases.ensureLoaded();
    final myName =
        aliases.meIdentity?.primary ??
        ProfileCacheService.instance.profile?.username;
    final session = sessionFromSharePayload(payload, myDisplayName: myName);
    if (session == null) throw Exception('Partie illisible');

    final gameTitle = payload['game_title']?.toString() ?? 'Jeu';
    final bggId = payload['bgg_id']?.toString();
    final history = GlobalPlayHistoryService();

    final items = await history.fetchBoardgameItems();
    final item = matchSharedPlayItem(items, gameTitle: gameTitle, bggId: bggId);
    if (item != null) {
      final existing = parseBoardgamePlays(item.metadata);
      if (isDuplicatePlay(existing, session)) {
        return 'Cette partie est déjà dans ton historique';
      }
      await history.saveSessionToItem(
        item,
        mergeSessionIntoHistory(existing, session),
      );
      CollectionRefresh.instance.bump();
      return 'Partie ajoutée à « ${item.title} »';
    }

    final orphans = await history.loadOrphans();
    if (isDuplicatePlay(orphans.map((o) => o.session), session)) {
      return 'Cette partie est déjà dans ton historique';
    }
    await history.addOrphan(
      OrphanBoardgamePlay(
        id: 'shared_${session.shareId ?? DateTime.now().microsecondsSinceEpoch}',
        title: gameTitle,
        bggId: bggId,
        imageUrl: payload['image_url']?.toString(),
        session: session,
      ),
    );
    return 'Partie ajoutée à ton historique global ($gameTitle)';
  }
}
