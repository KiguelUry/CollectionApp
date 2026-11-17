import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/services/collection_change_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CollectionChangeEvent round-trip JSON', () {
    final event = CollectionChangeEvent(
      id: 'e1',
      action: 'added',
      at: DateTime.utc(2026, 11, 1, 12),
      category: CollectionCategory.boardgame,
      title: 'Zenith',
      imageUrl: null,
      snapshot: const {'title': 'Zenith'},
      actorUsername: 'Kiki',
      detail: 'ajout',
    );
    final restored = CollectionChangeEvent.fromJson(event.toJson());
    expect(restored.id, 'e1');
    expect(restored.action, 'added');
    expect(restored.title, 'Zenith');
    expect(restored.actorUsername, 'Kiki');
    expect(restored.category, CollectionCategory.boardgame);
    expect(restored.detail, 'ajout');
    expect(restored.snapshot['title'], 'Zenith');
  });

  test('événements trop vieux hors TTL sont filtrables par date', () {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final fresh = CollectionChangeEvent(
      id: 'fresh',
      action: 'added',
      at: DateTime.now().subtract(const Duration(days: 2)),
      category: CollectionCategory.book,
      title: 'Manga',
      imageUrl: null,
      snapshot: const {},
    );
    final stale = CollectionChangeEvent(
      id: 'stale',
      action: 'deleted',
      at: cutoff.subtract(const Duration(days: 1)),
      category: CollectionCategory.book,
      title: 'Old',
      imageUrl: null,
      snapshot: const {},
    );
    final kept = [fresh, stale].where((e) => e.at.isAfter(cutoff)).toList();
    expect(kept.map((e) => e.id), ['fresh']);
  });
}
