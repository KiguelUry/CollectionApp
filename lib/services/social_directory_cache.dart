import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../utils/holder_label_utils.dart';
import 'friend_service.dart';
import 'group_service.dart';
import 'holder_place_history_service.dart';
import 'household_service.dart';

/// Amis, groupes, lieux et personnes en RAM pour ouvrir les feuilles sans attente.
class SocialDirectoryCache extends ChangeNotifier {
  SocialDirectoryCache._();
  static final instance = SocialDirectoryCache._();

  List<Map<String, dynamic>> friends = const [];
  List<CollectionGroup> groups = const [];
  final Map<String, List<Map<String, dynamic>>> membersByGroup = {};
  List<String> places = const [];
  List<String> people = const [];
  bool ready = false;

  Future<void>? _inflight;

  Future<void> warm() {
    final current = _inflight;
    if (current != null) return current;
    final run = _load();
    _inflight = run;
    return run.whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await HouseholdService.instance.ensureLoaded();
      final friendRows = await FriendService().fetchFriends();
      final groupRows = await GroupService().fetchMyGroups();
      final members = <String, List<Map<String, dynamic>>>{};
      final peopleSet = <String>{};
      final placeSet = <String>{};

      for (final home in HouseholdService.instance.homes) {
        if (home.place.trim().isNotEmpty) placeSet.add(home.place.trim());
        for (final p in home.people) {
          if (p.trim().isNotEmpty) peopleSet.add(p.trim());
        }
      }
      for (final f in friendRows) {
        final name = f['username']?.toString().trim() ?? '';
        if (name.isNotEmpty) peopleSet.add(name);
      }
      for (final g in groupRows) {
        try {
          final rows = await GroupService().fetchMembers(g.id);
          members[g.id] = rows;
          for (final m in rows) {
            final profile = m['profiles'] ?? m['profile'];
            final name = profile is Map
                ? profile['username']?.toString()
                : m['username']?.toString();
            if (name != null && name.trim().isNotEmpty) {
              peopleSet.add(name.trim());
            }
          }
        } catch (_) {}
      }

      final history = await HolderPlaceHistoryService.loadForGroups(
        const [],
        personalUserId: userId,
      );
      for (final raw in history) {
        _addPlace(placeSet, peopleSet, raw);
      }
      for (final g in groupRows) {
        final shared = await HolderPlaceHistoryService.loadForGroups([g.id]);
        for (final raw in shared) {
          _addPlace(placeSet, peopleSet, raw);
        }
      }

      try {
        // Pas de colonne location_label sur collection_items (prod) :
        // le lieu libre vit dans metadata.holder_label / metadata.location_label.
        final rows = await Supabase.instance.client
            .from('collection_items')
            .select('metadata')
            .or('added_by.eq.$userId,location_user_id.eq.$userId')
            .limit(400);
        for (final row in rows as List) {
          final meta = row['metadata'];
          if (meta is Map) {
            _addPlace(placeSet, peopleSet, meta['holder_label']?.toString());
            _addPlace(placeSet, peopleSet, meta['location_label']?.toString());
          }
        }
      } catch (_) {}

      friends = friendRows;
      groups = groupRows;
      membersByGroup
        ..clear()
        ..addAll(members);
      people = peopleSet.toList()..sort();
      places = placeSet.toList()..sort();
      ready = true;
      notifyListeners();
    } catch (e) {
      debugPrint('SocialDirectoryCache: $e');
    }
  }

  static void _addPlace(
    Set<String> places,
    Set<String> people,
    String? raw,
  ) {
    if (raw == null) return;
    final bare = holderLabelStorageValue(raw).trim();
    if (bare.isEmpty) return;
    final low = bare.toLowerCase();
    if (low == 'moi' || low == 'me' || low == 'chez moi') return;
    final knownPerson = people.any((p) => p.toLowerCase() == low);
    if (knownPerson) return;
    final prefixed = raw.trim().toLowerCase();
    final looksLikePlace = prefixed.startsWith('à ') ||
        prefixed.startsWith('a ') ||
        prefixed.startsWith('en ') ||
        prefixed.startsWith('au ') ||
        prefixed.startsWith('aux ');
    if (looksLikePlace || !prefixed.startsWith('chez ')) {
      places.add(bare);
    }
  }
}
