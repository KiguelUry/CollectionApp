import 'package:collection_app/models/app_notification.dart';
import 'package:collection_app/utils/notification_grouping.dart';
import 'package:collection_app/widgets/notifications/notification_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _now = DateTime(2026, 10, 15, 12);

AppNotification _n(
  String id,
  AppNotificationType type, {
  AppNotificationStatus status = AppNotificationStatus.unread,
  String sender = 'Alice',
  int minutesAgo = 5,
  Map<String, dynamic> extra = const {},
}) => AppNotification(
  id: id,
  recipientId: 'me',
  type: type,
  status: status,
  createdAt: _now.subtract(Duration(minutes: minutesAgo)),
  payload: {'sender_username': sender, ...extra},
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('cloche', () {
    testWidgets('pastille avec le nombre de non-lues', (tester) async {
      await tester.pumpWidget(
        _wrap(const NotificationBellButton(unreadCount: 6)),
      );
      final badge = tester.widget<Badge>(
        find.byKey(const ValueKey('notification_badge')),
      );
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('6'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    });

    testWidgets('pas de pastille à 0, 99+ au-delà de 99', (tester) async {
      await tester.pumpWidget(
        _wrap(const NotificationBellButton(unreadCount: 0)),
      );
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('notification_badge')))
            .isLabelVisible,
        isFalse,
      );
      await tester.pumpWidget(
        _wrap(const NotificationBellButton(unreadCount: 150)),
      );
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('tap déclenche l\'ouverture', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(NotificationBellButton(unreadCount: 1, onPressed: () => taps++)),
      );
      await tester.tap(find.byKey(const ValueKey('notification_bell')));
      expect(taps, 1);
    });
  });

  group('menu déroulant', () {
    testWidgets('6 demandes d\'ami groupées en une ligne cliquable', (
      tester,
    ) async {
      final rows = groupNotifications([
        for (final s in ['A', 'B', 'C', 'D', 'E', 'F'])
          _n('f$s', AppNotificationType.friendRequest, sender: s),
        _n(
          'r1',
          AppNotificationType.itemRecommendation,
          sender: 'Zoé',
          extra: {'title': 'Azul'},
          minutesAgo: 90,
        ),
      ]);
      NotificationRow? tapped;
      await tester.pumpWidget(
        _wrap(
          NotificationDropdownPanel(
            rows: rows,
            now: _now,
            onRowTap: (r) => tapped = r,
            onMarkAllRead: () {},
          ),
        ),
      );
      expect(find.text('6 personnes vous ont demandé en ami'), findsOneWidget);
      expect(find.textContaining('A, B et 4 autres'), findsOneWidget);
      expect(find.text('Zoé vous recommande « Azul »'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification_mark_all_read')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('notification_group_friend_request')),
      );
      expect(tapped!.isGroup, isTrue);
      expect(tapped!.count, 6);
    });

    testWidgets('état vide', (tester) async {
      await tester.pumpWidget(
        _wrap(NotificationDropdownPanel(rows: const [], onRowTap: (_) {})),
      );
      expect(find.text('Aucune notification pour le moment'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification_mark_all_read')),
        findsNothing,
      );
    });
  });

  group('vue détaillée', () {
    testWidgets('accepter / refuser appellent les actions', (tester) async {
      final accepted = <String>[];
      final declined = <String>[];
      await tester.pumpWidget(
        _wrap(
          NotificationDetailView(
            notifications: [
              _n('a', AppNotificationType.friendRequest, sender: 'Lou'),
              _n(
                'b',
                AppNotificationType.playShared,
                sender: 'Kiki',
                extra: {'game_title': 'Catan'},
              ),
            ],
            onAccept: (n) async => accepted.add(n.id),
            onDecline: (n) async => declined.add(n.id),
          ),
        ),
      );
      expect(find.text('Lou vous a demandé en ami'), findsOneWidget);
      expect(find.text('Accepter'), findsOneWidget);
      expect(find.text('Ajouter à mon historique'), findsOneWidget);
      expect(find.text('Ignorer'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification_accept_a')));
      await tester.tap(find.byKey(const ValueKey('notification_decline_b')));
      expect(accepted, ['a']);
      expect(declined, ['b']);
    });

    testWidgets('« Tout accepter » sur un groupe en attente', (tester) async {
      var all = 0;
      await tester.pumpWidget(
        _wrap(
          NotificationDetailView(
            notifications: [
              for (var i = 0; i < 3; i++)
                _n(
                  'r$i',
                  AppNotificationType.itemRecommendation,
                  extra: {'title': 'Jeu $i'},
                ),
            ],
            onAccept: (_) async {},
            onDecline: (_) async {},
            onAcceptAll: () => all++,
          ),
        ),
      );
      expect(find.text('Tout accepter (3)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notification_accept_all')));
      expect(all, 1);
      expect(find.text('Ajouter à ma wishlist'), findsNWidgets(3));
    });

    testWidgets('notification traitée : statut au lieu des boutons', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          NotificationDetailView(
            notifications: [
              _n(
                'a',
                AppNotificationType.groupInvite,
                status: AppNotificationStatus.accepted,
                extra: {'group_name': 'Famille'},
              ),
              _n(
                'b',
                AppNotificationType.friendRequest,
                status: AppNotificationStatus.declined,
              ),
            ],
            onAccept: (_) async {},
            onDecline: (_) async {},
          ),
        ),
      );
      expect(find.text('Accepté'), findsOneWidget);
      expect(find.text('Refusé'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification_accept_a')), findsNothing);
      expect(
        find.byKey(const ValueKey('notification_accept_all')),
        findsNothing,
      );
    });

    testWidgets('en cours de traitement : spinner', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NotificationDetailView(
            notifications: [_n('a', AppNotificationType.friendRequest)],
            busyIds: const {'a'},
            onAccept: (_) async {},
            onDecline: (_) async {},
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('notification_accept_a')), findsNothing);
    });
  });
}
