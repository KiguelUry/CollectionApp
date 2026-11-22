import 'package:collection_app/models/activity_event.dart';
import 'package:collection_app/models/app_notification.dart';
import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/models/collection_list_filters.dart';
import 'package:collection_app/services/friend_service.dart';
import 'package:collection_app/utils/activity_feed_grouper.dart';
import 'package:collection_app/utils/friend_item_overlap.dart';
import 'package:collection_app/utils/item_search.dart';
import 'package:collection_app/utils/notification_grouping.dart';
import 'package:collection_app/utils/wishlist_market_metadata.dart';
import 'package:collection_app/utils/wishlist_promote.dart';
import 'package:collection_app/widgets/item_customize_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

CollectionItem _game(
  String id,
  String title, {
  String? bggId,
  String? originalTitle,
  bool wishlist = false,
  String? addedBy,
  String? groupId,
  String? imageUrl,
  Map<String, dynamic>? extraMeta,
}) =>
    CollectionItem(
      id: id,
      title: title,
      category: CollectionCategory.boardgame,
      isWishlist: wishlist,
      addedBy: addedBy,
      groupId: groupId,
      imageUrl: imageUrl,
      metadata: {
        'bgg_id': ?bggId,
        'original_title': ?originalTitle,
        ...?extraMeta,
      },
    );

ActivityEvent _ev(
  String id, {
  String actor = 'a',
  String type = 'wishlist_added',
  String? itemId,
  String? title,
  required DateTime at,
}) =>
    ActivityEvent(
      id: id,
      actorId: actor,
      actorUsername: 'User$actor',
      eventType: type,
      itemId: itemId,
      itemTitle: title,
      createdAt: at,
    );

void main() {
  group('overlap / dédoublonnage catalogue', () {
    test('bgg_id prime : un jeu renommé reste « en commun »', () {
      final index = FriendOverlapIndex.fromMyRows([
        {
          'title': 'Esquissé !',
          'category': 'boardgame',
          'bgg_id': '46213',
          'original_title': 'Telestrations',
          'is_wishlist': false,
        },
        {'title': 'Azul', 'category': 'boardgame', 'is_wishlist': true},
      ]);
      expect(
        index.kindFor(_game('f1', 'Telestrations', bggId: '46213')),
        FriendOverlapKind.inCollection,
      );
      expect(
        index.kindFor(_game('f2', 'telestrations')),
        FriendOverlapKind.inCollection,
        reason: 'titre d\'origine reconnu sans bgg_id',
      );
      expect(index.kindFor(_game('f3', 'AZUL')), FriendOverlapKind.inWishlist);
      expect(index.kindFor(_game('f4', 'Cascadia')), FriendOverlapKind.none);
    });

    test('dedupeCatalogItems retire le Toy Battle ×3', () {
      final out = dedupeCatalogItems([
        _game('1', 'Toy Battle', bggId: '999'),
        _game('2', 'Toy Battle', bggId: '999'),
        _game('3', 'toy battle'),
        _game('4', 'Cascadia'),
      ]);
      expect(out.map((i) => i.id), ['1', '4']);
    });

    test('countIn compte les objets distincts', () {
      final index = FriendOverlapIndex.fromMyRows([
        {'title': 'Toy Battle', 'category': 'boardgame', 'is_wishlist': false},
      ]);
      final friend = [
        _game('1', 'Toy Battle'),
        _game('2', 'Toy Battle'),
        _game('3', 'Cascadia'),
      ];
      expect(index.countIn(friend, FriendOverlapKind.inCollection), 1);
      expect(index.countIn(friend, FriendOverlapKind.none), 1);
    });

    test('overlapKeysFor ignore un bgg_id vide ou "null"', () {
      expect(
        overlapKeysFor(categoryDb: 'boardgame', title: 'X', bggId: 'null'),
        {'boardgame|x'},
      );
    });
  });

  group('visibilité collection ami', () {
    const friend = 'friend';
    test('mes objets ne fuient pas chez l\'ami', () {
      expect(
        FriendService.isFriendOwnedVisible(
          _game('1', 'A', addedBy: 'me'),
          friend,
          const {},
        ),
        isFalse,
      );
    });
    test('objet perso de l\'ami visible', () {
      expect(
        FriendService.isFriendOwnedVisible(
          _game('1', 'A', addedBy: friend),
          friend,
          const {},
        ),
        isTrue,
      );
    });
    test('objet de groupe : seulement si groupe commun', () {
      final item = _game('1', 'A', addedBy: friend, groupId: 'g1');
      expect(
        FriendService.isFriendOwnedVisible(item, friend, const {}),
        isFalse,
      );
      expect(
        FriendService.isFriendOwnedVisible(item, friend, const {'g1'}),
        isTrue,
      );
    });
  });

  group('matchCatalogDuplicate', () {
    final rows = [
      {'id': 'a', 'title': 'Esquissé !', 'bgg_id': '46213'},
      {'id': 'b', 'title': 'Azul', 'original_title': 'Azul (FR)'},
    ];
    test('par bgg_id même si le titre diffère', () {
      expect(
        matchCatalogDuplicate(rows, title: 'Telestrations', bggId: '46213')?[
            'id'],
        'a',
      );
    });
    test('par titre d\'origine', () {
      expect(matchCatalogDuplicate(rows, title: 'azul (fr)')?['id'], 'b');
    });
    test('aucun doublon', () {
      expect(matchCatalogDuplicate(rows, title: 'Cascadia'), isNull);
    });
  });

  group('recherche 2 noms', () {
    test('normalizeSearchText retire accents et ponctuation', () {
      expect(normalizeSearchText('Esquissé !'), 'esquisse');
    });
    test('trouve un jeu renommé par son titre BGG', () {
      final item = _game('1', 'Esquissé !', originalTitle: 'Telestrations');
      expect(itemMatchesSearch(item, 'teles'), isTrue);
      expect(itemMatchesSearch(item, 'esquisse'), isTrue);
      expect(itemMatchesSearch(item, 'azul'), isFalse);
      expect(originalTitleOf(item), 'Telestrations');
    });
    test('les filtres de collection utilisent les 2 noms', () {
      final items = [
        _game('1', 'Esquissé !', originalTitle: 'Telestrations'),
        _game('2', 'Azul'),
      ];
      final out =
          CollectionListFilters(searchQuery: 'telestr').apply(items);
      expect(out.map((i) => i.id), ['1']);
    });
  });

  group('applyItemCustomization', () {
    final base = _game('1', 'Telestrations', imageUrl: 'https://bgg/t.jpg');

    test('renommer garde le titre BGG', () {
      final c = applyItemCustomization(
        base,
        title: 'Esquissé !',
        imageUrl: base.imageUrl,
      );
      expect(c.title, 'Esquissé !');
      expect(c.metadata['original_title'], 'Telestrations');
      expect(c.metadata.containsKey('custom_image'), isFalse);
    });

    test('image perso puis restauration', () {
      final custom = applyItemCustomization(
        base,
        title: base.title,
        imageUrl: 'https://storage/me.jpg',
      );
      expect(custom.metadata['original_image_url'], 'https://bgg/t.jpg');
      expect(custom.metadata['custom_image'], isTrue);
      expect(custom.metadata.containsKey('original_title'), isFalse);

      final customized = _game(
        '1',
        custom.title,
        imageUrl: custom.imageUrl,
        extraMeta: custom.metadata,
      );
      final restored = applyItemCustomization(
        customized,
        title: base.title,
        imageUrl: null,
      );
      expect(restored.imageUrl, 'https://bgg/t.jpg');
      expect(restored.metadata.containsKey('custom_image'), isFalse);
      expect(restored.metadata.containsKey('original_image_url'), isFalse);
    });

    test('revenir au titre BGG retire original_title', () {
      final renamed = _game(
        '1',
        'Esquissé !',
        originalTitle: 'Telestrations',
        imageUrl: base.imageUrl,
      );
      final c = applyItemCustomization(
        renamed,
        title: 'telestrations',
        imageUrl: renamed.imageUrl,
      );
      expect(c.metadata.containsKey('original_title'), isFalse);
    });
  });

  group('estimations wishlist / budget', () {
    final meta = {
      kMarketSecondhandPrice: 18,
      kMarketNewPriceMin: '29,90',
    };
    test('libellé occasion + neuf', () {
      expect(marketEstimateLabel(meta), 'Occasion ≈ 18 € · Neuf dès 30 €');
      expect(marketEstimateLabel(const {}), isNull);
    });
    test('dans ton budget', () {
      expect(isWithinBudget(meta, 20), isTrue);
      expect(isWithinBudget(meta, 15), isFalse);
      expect(isWithinBudget(meta, null), isFalse);
      expect(isWithinBudget({kMarketNewPriceMin: 25}, 25), isTrue);
    });
  });

  group('fil d\'activité', () {
    final t0 = DateTime(2026, 11, 22, 12);
    test('3 ajouts identiques → 1 seul', () {
      final out = dedupeActivityEvents([
        _ev('1', itemId: 'i1', title: 'Toy Battle', at: t0),
        _ev('2', itemId: 'i2', title: 'Toy Battle', at: t0),
        _ev('3', itemId: 'i3', title: 'toy battle', at: t0),
      ]);
      expect(out.map((e) => e.id), ['1']);
    });
    test('objet supprimé (ni id ni titre) masqué', () {
      expect(dedupeActivityEvents([_ev('1', at: t0)]), isEmpty);
    });
    test('acteurs différents conservés', () {
      final out = dedupeActivityEvents([
        _ev('1', actor: 'a', title: 'Azul', itemId: 'x', at: t0),
        _ev('2', actor: 'b', title: 'Azul', itemId: 'y', at: t0),
      ]);
      expect(out, hasLength(2));
    });
    test('hors fenêtre de 24 h : conservé', () {
      final out = dedupeActivityEvents([
        _ev('1', title: 'Azul', itemId: 'x', at: t0),
        _ev('2',
            title: 'Azul',
            itemId: 'x',
            at: t0.subtract(const Duration(days: 2))),
      ]);
      expect(out, hasLength(2));
    });
  });

  group('notifications', () {
    final now = DateTime(2026, 11, 22, 15);
    test('périodes Aujourd\'hui / Cette semaine / Plus ancien', () {
      expect(
        notificationPeriodOf(DateTime(2026, 11, 22, 1), now),
        NotificationPeriod.today,
      );
      expect(
        notificationPeriodOf(DateTime(2026, 11, 19), now),
        NotificationPeriod.thisWeek,
      );
      expect(
        notificationPeriodOf(DateTime(2026, 11, 1), now),
        NotificationPeriod.older,
      );
    });

    test('rowsByPeriod ordonne les sections', () {
      AppNotification n(String id, DateTime at) => AppNotification(
            id: id,
            recipientId: 'me',
            type: AppNotificationType.playShared,
            status: AppNotificationStatus.read,
            createdAt: at,
            payload: const {'sender_username': 'Bob'},
          );
      final rows = groupNotifications([
        n('a', DateTime(2026, 11, 22, 10)),
        n('b', DateTime(2026, 11, 20)),
        n('c', DateTime(2026, 10, 1)),
      ]);
      final byPeriod = rowsByPeriod(rows, now);
      expect(byPeriod.keys, [
        NotificationPeriod.today,
        NotificationPeriod.thisWeek,
        NotificationPeriod.older,
      ]);
    });

    test('repli payload.kind → borrow_request', () {
      final n = AppNotification.tryFromJson({
        'id': 'x',
        'recipient_id': 'me',
        'type': 'item_recommendation',
        'status': 'unread',
        'payload': {'kind': 'borrow_request', 'item_title': 'Azul'},
        'created_at': '2026-11-22T10:00:00Z',
      })!;
      expect(n.type, AppNotificationType.borrowRequest);
      expect(n.isInformational, isFalse);
    });

    test('friend_accepted est informatif', () {
      final n = AppNotification.tryFromJson({
        'id': 'x',
        'recipient_id': 'me',
        'type': 'friend_accepted',
        'status': 'unread',
        'payload': const {},
        'created_at': '2026-11-22T10:00:00Z',
      })!;
      expect(n.isInformational, isTrue);
    });
  });
}
