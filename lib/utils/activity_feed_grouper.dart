import '../models/activity_event.dart';

/// Regroupe les rafales d'ajouts du même ami pour un fil plus lisible.
class ActivityFeedGroup {
  final List<ActivityEvent> events;

  const ActivityFeedGroup(this.events);

  ActivityEvent get head => events.first;

  bool get isBurst => events.length > 1;

  int get count => events.length;

  DateTime get createdAt => head.createdAt;

  String summaryLabel(ActivityEvent e) {
    final name = e.actorUsername;
    if (!isBurst) return e.description;
    final n = count;
    return switch (e.eventType) {
      'item_added' => '$name a ajouté $n objet${n > 1 ? 's' : ''}',
      'wishlist_added' =>
        '$name a mis $n objet${n > 1 ? 's' : ''} en wishlist',
      _ => e.description,
    };
  }
}

List<ActivityFeedGroup> groupActivityEvents(List<ActivityEvent> events) {
  if (events.isEmpty) return [];

  final groups = <ActivityFeedGroup>[];
  var current = <ActivityEvent>[events.first];

  for (var i = 1; i < events.length; i++) {
    final e = events[i];
    final head = current.first;
    if (_mergeable(head, e)) {
      current.add(e);
    } else {
      groups.add(ActivityFeedGroup(List.unmodifiable(current)));
      current = [e];
    }
  }
  groups.add(ActivityFeedGroup(List.unmodifiable(current)));
  return groups;
}

bool _mergeable(ActivityEvent newer, ActivityEvent older) {
  if (newer.actorId != older.actorId) return false;
  if (newer.eventType != older.eventType) return false;
  if (!{'item_added', 'wishlist_added'}.contains(newer.eventType)) {
    return false;
  }
  final gap = newer.createdAt.difference(older.createdAt);
  return gap.inHours <= 3;
}
