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

/// Retire les événements identiques (même personne, même type, même objet ou
/// même titre) à moins de [window] d'écart — ex. triple ajout wishlist —
/// ainsi que les ajouts dont l'objet a été supprimé depuis.
/// [events] est trié du plus récent au plus ancien ; on garde le plus récent.
List<ActivityEvent> dedupeActivityEvents(
  List<ActivityEvent> events, {
  Duration window = const Duration(hours: 24),
}) {
  const itemEvents = {'item_added', 'wishlist_added', 'item_rated'};
  final lastSeen = <String, DateTime>{};
  final out = <ActivityEvent>[];
  for (final e in events) {
    final title = e.itemTitle?.trim().toLowerCase();
    if (itemEvents.contains(e.eventType) &&
        e.itemId == null &&
        (title == null || title.isEmpty)) {
      continue;
    }
    final identity = (title != null && title.isNotEmpty)
        ? 't:$title'
        : (e.itemId != null ? 'i:${e.itemId}' : 'e:${e.id}');
    final key = '${e.actorId}|${e.eventType}|$identity';
    final seenAt = lastSeen[key];
    if (seenAt != null && seenAt.difference(e.createdAt).abs() <= window) {
      continue;
    }
    lastSeen[key] = e.createdAt;
    out.add(e);
  }
  return out;
}

List<ActivityFeedGroup> groupActivityEvents(List<ActivityEvent> events) {
  events = dedupeActivityEvents(events);
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
