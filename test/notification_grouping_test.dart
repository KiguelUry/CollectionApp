import 'package:collection_app/models/app_notification.dart';
import 'package:collection_app/utils/notification_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 15, 12);

AppNotification _n(
  String id,
  AppNotificationType type, {
  int minutesAgo = 0,
  AppNotificationStatus status = AppNotificationStatus.unread,
  String sender = 'Alice',
  Map<String, dynamic> extra = const {},
}) {
  return AppNotification(
    id: id,
    recipientId: 'me',
    senderId: 's_$sender',
    type: type,
    status: status,
    createdAt: _t0.subtract(Duration(minutes: minutesAgo)),
    payload: {'sender_username': sender, ...extra},
  );
}

void main() {
  group('groupNotifications', () {
    test('3 non-lues du même type → une seule ligne groupée', () {
      final rows = groupNotifications([
        _n('a', AppNotificationType.friendRequest, minutesAgo: 1, sender: 'A'),
        _n('b', AppNotificationType.friendRequest, minutesAgo: 2, sender: 'B'),
        _n('c', AppNotificationType.friendRequest, minutesAgo: 3, sender: 'C'),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.isGroup, isTrue);
      expect(rows.single.count, 3);
      expect(rows.single.title, '3 personnes vous ont demandé en ami');
      expect(rows.single.items.map((n) => n.id), ['a', 'b', 'c']);
    });

    test('2 non-lues du même type restent séparées', () {
      final rows = groupNotifications([
        _n('a', AppNotificationType.itemRecommendation),
        _n('b', AppNotificationType.itemRecommendation, minutesAgo: 5),
      ]);
      expect(rows, hasLength(2));
      expect(rows.every((r) => !r.isGroup), isTrue);
    });

    test('6 demandes d\'ami + 3 recommandations → 2 groupes', () {
      final rows = groupNotifications([
        for (var i = 0; i < 6; i++)
          _n('f$i', AppNotificationType.friendRequest, minutesAgo: 10 + i),
        for (var i = 0; i < 3; i++)
          _n('r$i', AppNotificationType.itemRecommendation, minutesAgo: i),
      ]);
      expect(rows, hasLength(2));
      expect(rows[0].title, '3 objets vous ont été recommandés');
      expect(rows[1].title, '6 personnes vous ont demandé en ami');
    });

    test('les notifications lues ou traitées ne sont jamais groupées', () {
      final rows = groupNotifications([
        _n(
          'a',
          AppNotificationType.playShared,
          status: AppNotificationStatus.read,
        ),
        _n(
          'b',
          AppNotificationType.playShared,
          status: AppNotificationStatus.accepted,
        ),
        _n(
          'c',
          AppNotificationType.playShared,
          status: AppNotificationStatus.declined,
        ),
        _n('d', AppNotificationType.playShared),
      ]);
      expect(rows, hasLength(4));
      expect(rows.where((r) => r.isGroup), isEmpty);
    });

    test('groupe des non-lues + lues du même type à part', () {
      final rows = groupNotifications([
        for (var i = 0; i < 3; i++)
          _n('u$i', AppNotificationType.groupInvite, minutesAgo: i),
        _n(
          'old',
          AppNotificationType.groupInvite,
          minutesAgo: 90,
          status: AppNotificationStatus.read,
        ),
      ]);
      expect(rows, hasLength(2));
      expect(rows.first.isGroup, isTrue);
      expect(rows.first.count, 3);
      expect(rows.last.items.single.id, 'old');
    });

    test('tri du plus récent au plus ancien (groupe = sa plus récente)', () {
      final rows = groupNotifications([
        _n('single', AppNotificationType.playShared, minutesAgo: 5),
        _n('g1', AppNotificationType.friendRequest, minutesAgo: 1),
        _n('g2', AppNotificationType.friendRequest, minutesAgo: 30),
        _n('g3', AppNotificationType.friendRequest, minutesAgo: 40),
        _n('older', AppNotificationType.itemRecommendation, minutesAgo: 60),
      ]);
      expect(rows.map((r) => r.isGroup ? 'group' : r.items.first.id), [
        'group',
        'single',
        'older',
      ]);
    });

    test('seuil configurable', () {
      final rows = groupNotifications([
        _n('a', AppNotificationType.playShared),
        _n('b', AppNotificationType.playShared),
      ], threshold: 2);
      expect(rows.single.isGroup, isTrue);
      expect(rows.single.title, '2 parties ont été partagées avec vous');
    });

    test('liste vide', () {
      expect(groupNotifications(const []), isEmpty);
      expect(unreadNotificationCount(const []), 0);
    });
  });

  test('compteur non-lues', () {
    expect(
      unreadNotificationCount([
        _n('a', AppNotificationType.playShared),
        _n(
          'b',
          AppNotificationType.playShared,
          status: AppNotificationStatus.read,
        ),
        _n('c', AppNotificationType.friendRequest),
      ]),
      2,
    );
  });

  test('titres individuels', () {
    expect(
      notificationTitle(
        _n('a', AppNotificationType.friendRequest, sender: 'Lou'),
      ),
      'Lou vous a demandé en ami',
    );
    expect(
      notificationTitle(
        _n(
          'b',
          AppNotificationType.groupInvite,
          sender: 'Max',
          extra: {'group_name': 'Famille'},
        ),
      ),
      'Max vous invite dans le groupe « Famille »',
    );
    expect(
      notificationTitle(
        _n(
          'c',
          AppNotificationType.itemRecommendation,
          sender: 'Zoé',
          extra: {'title': 'Azul'},
        ),
      ),
      'Zoé vous recommande « Azul »',
    );
    expect(
      notificationTitle(
        _n(
          'd',
          AppNotificationType.playShared,
          sender: 'Kiki',
          extra: {'game_title': 'Catan'},
        ),
      ),
      'Kiki a enregistré une partie de Catan avec vous. '
      'Voulez-vous l\'ajouter à votre historique ?',
    );
  });

  test('résumé des expéditeurs', () {
    expect(
      groupedSenderSummary([
        _n('a', AppNotificationType.friendRequest, sender: 'A'),
        _n('b', AppNotificationType.friendRequest, sender: 'B'),
      ]),
      'A et B',
    );
    expect(
      groupedSenderSummary([
        for (final s in ['A', 'B', 'C', 'D', 'E', 'F'])
          _n(s, AppNotificationType.friendRequest, sender: s),
      ]),
      'A, B et 4 autres',
    );
    expect(
      groupedSenderSummary([
        for (final s in ['A', 'B', 'C'])
          _n(s, AppNotificationType.friendRequest, sender: s),
      ]),
      'A, B et 1 autre',
    );
  });

  group('AppNotification.tryFromJson', () {
    test('parse une ligne Supabase', () {
      final n = AppNotification.tryFromJson({
        'id': 'x',
        'recipient_id': 'me',
        'sender_id': 'you',
        'type': 'play_shared',
        'status': 'read',
        'payload': {'game_title': 'Azul'},
        'created_at': '2026-10-15T10:00:00Z',
      })!;
      expect(n.type, AppNotificationType.playShared);
      expect(n.status, AppNotificationStatus.read);
      expect(n.isPending, isTrue);
      expect(n.isUnread, isFalse);
      expect(n.payload['game_title'], 'Azul');
    });

    test('type inconnu → null (ignoré)', () {
      expect(
        AppNotification.tryFromJson({'id': 'x', 'type': 'future_type'}),
        isNull,
      );
    });
  });
}
