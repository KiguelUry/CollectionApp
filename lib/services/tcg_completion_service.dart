import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_subcategory.dart';
import '../models/collection_category.dart';
import '../models/tcg_completion_summary.dart';
import '../utils/collection_item_scope.dart';

/// Agrège la progression TCG depuis la collection locale (pas d’API catalogue).
class TcgCompletionService {
  final _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<TcgSubcategoryStats>> fetchSubcategoryStats() async {
    final userId = _userId;
    if (userId == null) return [];

    final rows = await CollectionItemScope.personal(
      _client
          .from('collection_items')
          .select('subcategory, metadata')
          .eq('category', CollectionCategory.card.dbValue)
          .eq('is_wishlist', false),
      userId: userId,
    );

    final ownedBySub = <String, int>{};
    final setCounts = <String, Map<String, _SetAgg>>{};

    for (final raw in rows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      final sub = map['subcategory']?.toString() ?? '';
      if (sub.isEmpty) continue;

      ownedBySub[sub] = (ownedBySub[sub] ?? 0) + 1;

      final meta = map['metadata'] as Map<String, dynamic>?;
      final setId = meta?['set_id']?.toString().trim();
      final setCode = meta?['set_code']?.toString().trim();
      final setName = meta?['set_name']?.toString().trim();
      final key = (setId != null && setId.isNotEmpty)
          ? setId
          : (setCode != null && setCode.isNotEmpty ? setCode : null);
      if (key == null) continue;

      setCounts.putIfAbsent(sub, () => {});
      final agg = setCounts[sub]!.putIfAbsent(
        key,
        () => _SetAgg(name: setName),
      );
      agg.owned += 1;
      if ((agg.name == null || agg.name!.isEmpty) &&
          setName != null &&
          setName.isNotEmpty) {
        agg.name = setName;
      }
    }

    final out = <TcgSubcategoryStats>[];
    for (final sub in CardSubcategory.hubOrder) {
      if (!sub.hasSetBrowser) continue;
      final owned = ownedBySub[sub.dbValue] ?? 0;
      final sets = setCounts[sub.dbValue];
      final topSets = <TcgSetProgressRow>[];
      if (sets != null) {
        final entries = sets.entries.toList()
          ..sort((a, b) => b.value.owned.compareTo(a.value.owned));
        for (final e in entries.take(8)) {
          topSets.add(
            TcgSetProgressRow(
              setKey: e.key,
              setName: e.value.name,
              owned: e.value.owned,
            ),
          );
        }
      }
      out.add(
        TcgSubcategoryStats(
          subcategory: sub,
          ownedCards: owned,
          setsTouched: sets?.length ?? 0,
          topSets: topSets,
        ),
      );
    }
    return out;
  }

  Future<int> totalOwnedCards() async {
    final stats = await fetchSubcategoryStats();
    return stats.fold<int>(0, (sum, s) => sum + s.ownedCards);
  }
}

class _SetAgg {
  String? name;
  int owned = 0;

  _SetAgg({this.name});
}
