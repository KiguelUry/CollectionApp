import 'package:collection_app/models/activity_event.dart';
import 'package:collection_app/utils/activity_feed_grouper.dart';
import 'package:flutter_test/flutter_test.dart';

ActivityEvent _ev({
  required String id,
  required String actor,
  required String type,
  required DateTime at,
  String? title,
}) {
  return ActivityEvent(
    id: id,
    actorId: actor,
    actorUsername: 'User$actor',
    eventType: type,
    itemId: 'item-$id',
    itemTitle: title ?? 'Item $id',
    createdAt: at,
  );
}

void main() {
  test('regroupe les ajouts du même ami dans une fenêtre de 3 h', () {
    final now = DateTime(2026, 11, 16, 18);
    final events = [
      _ev(id: '1', actor: 'a', type: 'item_added', at: now),
      _ev(id: '2', actor: 'a', type: 'item_added', at: now.subtract(const Duration(hours: 1))),
      _ev(id: '3', actor: 'a', type: 'item_added', at: now.subtract(const Duration(hours: 2))),
    ];
    final groups = groupActivityEvents(events);
    expect(groups.length, 1);
    expect(groups.first.isBurst, isTrue);
    expect(groups.first.count, 3);
    expect(groups.first.summaryLabel(groups.first.head), contains('3 objets'));
  });

  test('ne fusionne pas notes et ajouts', () {
    final now = DateTime(2026, 11, 16, 18);
    final events = [
      _ev(id: '1', actor: 'a', type: 'item_rated', at: now),
      _ev(id: '2', actor: 'a', type: 'item_added', at: now.subtract(const Duration(minutes: 5))),
    ];
    final groups = groupActivityEvents(events);
    expect(groups.length, 2);
    expect(groups.every((g) => !g.isBurst), isTrue);
  });

  test('ne fusionne pas deux acteurs différents', () {
    final now = DateTime(2026, 11, 16, 18);
    final events = [
      _ev(id: '1', actor: 'a', type: 'item_added', at: now),
      _ev(id: '2', actor: 'b', type: 'item_added', at: now.subtract(const Duration(minutes: 5))),
    ];
    expect(groupActivityEvents(events).length, 2);
  });

  test('coupe si écart > 3 heures', () {
    final now = DateTime(2026, 11, 16, 18);
    final events = [
      _ev(id: '1', actor: 'a', type: 'item_added', at: now),
      _ev(
        id: '2',
        actor: 'a',
        type: 'item_added',
        at: now.subtract(const Duration(hours: 4)),
      ),
    ];
    expect(groupActivityEvents(events).length, 2);
  });

  test('liste vide → aucun groupe', () {
    expect(groupActivityEvents(const []), isEmpty);
  });
}
