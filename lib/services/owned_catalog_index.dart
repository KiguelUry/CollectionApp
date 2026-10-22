import '../models/collection_item.dart';
import 'user_boardgame_collection_service.dart';

/// Index mémoire : jeux possédés (perso + groupes) pour badges Wishlist.
class OwnedElsewhereInfo {
  final int count;
  final bool personal;
  final List<String> groupLabels;

  const OwnedElsewhereInfo({
    required this.count,
    required this.personal,
    this.groupLabels = const [],
  });

  String get chipLabel {
    if (personal && groupLabels.isEmpty) return '📦 Possédé ($count)';
    if (!personal && groupLabels.isNotEmpty) {
      return '👥 Groupe ($count)';
    }
    return '👥 Possédé ($count)';
  }

  String get detailLabel {
    final parts = <String>[];
    if (personal) parts.add('Perso');
    for (final g in groupLabels) {
      parts.add(g);
    }
    if (parts.isEmpty) return 'Possédé : $count';
    return 'Possédé : $count (${parts.join(' · ')})';
  }
}

abstract final class OwnedCatalogIndex {
  static final Map<String, OwnedElsewhereInfo> _byKey = {};

  static OwnedElsewhereInfo? lookup(CollectionItem item) {
    final key = UserBoardgameCollectionService.catalogKeyFromMetadata(
      item.metadata,
      item.title,
    );
    return _byKey[key];
  }

  static OwnedElsewhereInfo? lookupKey(String key) => _byKey[key];

  /// Reconstruit depuis la collection active (hors wishlist / vendus).
  static void rebuild(Iterable<CollectionItem> items) {
    _byKey.clear();
    final acc = <String, _Acc>{};
    for (final item in items) {
      if (item.isWishlist || item.isSold) continue;
      final key = UserBoardgameCollectionService.catalogKeyFromMetadata(
        item.metadata,
        item.title,
      );
      final a = acc.putIfAbsent(key, _Acc.new);
      a.count++;
      if (item.groupId != null && item.groupId!.isNotEmpty) {
        final name = item.groupName?.trim();
        final loc = item.locationLabel?.trim();
        final label = [
          if (name != null && name.isNotEmpty) name,
          if (loc != null && loc.isNotEmpty) loc,
        ].join(' · ');
        if (label.isNotEmpty) a.groups.add(label);
      } else {
        a.personal = true;
      }
    }
    for (final e in acc.entries) {
      _byKey[e.key] = OwnedElsewhereInfo(
        count: e.value.count,
        personal: e.value.personal,
        groupLabels: e.value.groups.toList(),
      );
    }
  }
}

class _Acc {
  int count = 0;
  bool personal = false;
  final Set<String> groups = {};
}
