import 'dart:math';

import 'package:collection_app/models/boardgame_play_session.dart';
import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/services/player_alias_service.dart';
import 'package:collection_app/utils/play_share.dart';
import 'package:flutter_test/flutter_test.dart';

BoardgamePlaySession _session({
  List<String> players = const ['Kiki', 'Igor', 'Lou'],
  String? winner = 'Igor',
  DateTime? date,
  String? shareId,
}) => BoardgamePlaySession(
  date: date ?? DateTime(2026, 10, 14),
  players: players,
  winner: winner,
  scores: {for (final p in players) p: 10},
  shareId: shareId,
);

CollectionItem _item(String id, String title, {String? bggId}) =>
    CollectionItem(
      id: id,
      title: title,
      category: CollectionCategory.boardgame,
      isWishlist: false,
      metadata: {'bgg_id': ?bggId},
    );

void main() {
  group('shareId', () {
    test('aller-retour JSON et copyWith', () {
      final s = _session(shareId: 'ps_abc');
      final back = BoardgamePlaySession.fromJson(s.toJson());
      expect(back.shareId, 'ps_abc');
      expect(back.copyWith(notes: 'x').shareId, 'ps_abc');
      expect(
        BoardgamePlaySession.fromJson(_session().toJson()).shareId,
        isNull,
      );
    });

    test('identifiants uniques', () {
      final r = Random(1);
      final ids = {for (var i = 0; i < 50; i++) newPlayShareId(random: r)};
      expect(ids, hasLength(50));
      expect(ids.first, startsWith('ps_'));
      expect(playShareDedupeKey('ps_1'), 'play:ps_1');
    });
  });

  group('payload de partage', () {
    test('mes pseudos deviennent mon nom de compte', () {
      final payload = buildPlaySharePayload(
        session: _session(winner: 'Kiki'),
        shareId: 'ps_1',
        gameTitle: 'Catan',
        senderUsername: 'kilian',
        senderAliases: const ['Kiki', 'Moi'],
        recipientPlayerName: 'Igor',
        bggId: '13',
      );
      expect(payload['share_id'], 'ps_1');
      expect(payload['game_title'], 'Catan');
      expect(payload['bgg_id'], '13');
      expect(payload['as_player'], 'Igor');
      final s = BoardgamePlaySession.fromJson(
        Map<String, dynamic>.from(payload['session'] as Map),
      );
      expect(s.players, ['kilian', 'Igor', 'Lou']);
      expect(s.winner, 'kilian');
      expect(s.shareId, 'ps_1');
      expect(s.scores!.keys, contains('kilian'));
    });

    test('import : mon pseudo dans la partie devient mon nom affiché', () {
      final payload = buildPlaySharePayload(
        session: _session(),
        shareId: 'ps_2',
        gameTitle: 'Catan',
        senderUsername: 'kilian',
        senderAliases: const ['Kiki'],
        recipientPlayerName: 'Igor',
      );
      final s = sessionFromSharePayload(payload, myDisplayName: 'Igor B.')!;
      expect(s.players, ['kilian', 'Igor B.', 'Lou']);
      expect(s.winner, 'Igor B.');
      expect(s.shareId, 'ps_2');
    });

    test('import sans nom connu : session inchangée', () {
      final payload = buildPlaySharePayload(
        session: _session(),
        shareId: 'ps_3',
        gameTitle: 'Catan',
        senderUsername: 'kilian',
        recipientPlayerName: 'Igor',
      );
      expect(sessionFromSharePayload(payload)!.players, [
        'Kiki',
        'Igor',
        'Lou',
      ]);
      expect(sessionFromSharePayload(const {}), isNull);
    });
  });

  group('anti-doublon', () {
    test('même shareId → doublon', () {
      final existing = [_session(shareId: 'ps_1', date: DateTime(2025))];
      expect(isDuplicatePlay(existing, _session(shareId: 'ps_1')), isTrue);
    });

    test(
      'même jour + mêmes joueurs (ordre/casse) + même gagnant → doublon',
      () {
        final existing = [
          _session(players: const ['lou', 'IGOR', 'kiki'], winner: 'igor'),
        ];
        expect(isDuplicatePlay(existing, _session(shareId: 'ps_new')), isTrue);
      },
    );

    test('autre jour, autres joueurs ou autre gagnant → pas doublon', () {
      final incoming = _session(shareId: 'ps_x');
      expect(
        isDuplicatePlay([_session(date: DateTime(2026, 10, 13))], incoming),
        isFalse,
      );
      expect(
        isDuplicatePlay([
          _session(players: const ['Kiki', 'Igor']),
        ], incoming),
        isFalse,
      );
      expect(isDuplicatePlay([_session(winner: 'Lou')], incoming), isFalse);
      expect(isDuplicatePlay(const [], incoming), isFalse);
    });

    test('deux vraies parties le même jour avec des shareId différents', () {
      final existing = [_session(shareId: 'ps_a', winner: 'Lou')];
      expect(isDuplicatePlay(existing, _session(shareId: 'ps_b')), isFalse);
    });
  });

  group('jeu cible chez le destinataire', () {
    final items = [
      _item('1', 'Les Aventuriers du Rail'),
      _item('2', 'CATAN', bggId: '13'),
      _item('3', 'Azul'),
    ];

    test('BGG id prioritaire', () {
      expect(
        matchSharedPlayItem(items, gameTitle: 'Catan (FR)', bggId: '13')!.id,
        '2',
      );
    });

    test('sinon titre normalisé', () {
      expect(matchSharedPlayItem(items, gameTitle: '  azul ')!.id, '3');
    });

    test('jeu non possédé → null (partie orpheline)', () {
      expect(
        matchSharedPlayItem(items, gameTitle: 'Dune', bggId: '999'),
        isNull,
      );
    });
  });

  group('lien pseudo ↔ ami', () {
    const identities = [
      PlayerIdentity(
        id: 'me',
        names: ['Kiki'],
        displayName: 'Kiki',
        isMe: true,
      ),
      PlayerIdentity(
        id: 'i1',
        names: ['Igor', 'Igo'],
        displayName: 'Igor',
        friendProfileId: 'p_igor',
        friendUsername: 'igor42',
      ),
      PlayerIdentity(id: 'i2', names: ['Lou'], displayName: 'Lou'),
    ];

    test('seuls les joueurs liés à un ami (hors moi) sont retenus', () {
      final linked = linkedFriendsAmong(['Kiki', 'igo', 'Lou'], identities);
      expect(linked, hasLength(1));
      expect(linked.single.playerName, 'igo');
      expect(linked.single.profileId, 'p_igor');
      expect(linked.single.username, 'igor42');
    });

    test('un compte ami notifié une seule fois même avec 2 alias', () {
      expect(linkedFriendsAmong(['Igor', 'Igo'], identities), hasLength(1));
    });

    test('applyFriendLink lie une identité existante', () {
      final next = applyFriendLink(
        identities,
        name: 'lou',
        profileId: 'p_lou',
        username: 'loulou',
        newId: 'new',
      );
      final lou = next.firstWhere((i) => i.id == 'i2');
      expect(lou.friendProfileId, 'p_lou');
      expect(lou.friendUsername, 'loulou');
      expect(next, hasLength(3));
    });

    test('applyFriendLink crée l\'identité si le pseudo est inconnu', () {
      final next = applyFriendLink(
        identities,
        name: 'Zoé',
        profileId: 'p_zoe',
        username: 'zoe',
        newId: 'new',
      );
      expect(next, hasLength(4));
      expect(next.last.names, ['Zoé']);
      expect(next.last.friendProfileId, 'p_zoe');
    });

    test('un compte ami ne reste lié qu\'à une identité', () {
      final next = applyFriendLink(
        identities,
        name: 'Lou',
        profileId: 'p_igor',
        username: 'igor42',
        newId: 'new',
      );
      expect(next.firstWhere((i) => i.id == 'i1').isLinkedToFriend, isFalse);
      expect(next.firstWhere((i) => i.id == 'i2').friendProfileId, 'p_igor');
    });

    test('PlayerIdentity JSON conserve le lien ami', () {
      final back = PlayerIdentity.fromJson(identities[1].toJson());
      expect(back.friendProfileId, 'p_igor');
      expect(back.friendUsername, 'igor42');
      final plain = PlayerIdentity.fromJson(identities[2].toJson());
      expect(plain.isLinkedToFriend, isFalse);
      expect(
        identities[1].copyWith(clearFriend: true).isLinkedToFriend,
        isFalse,
      );
    });
  });
}
