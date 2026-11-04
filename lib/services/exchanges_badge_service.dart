import 'package:shared_preferences/shared_preferences.dart';

import '../models/collection_item.dart';

/// Badge rouge du menu « Prêts & échanges » :
/// - éléments apparus depuis la dernière visite
/// - +1 par semaine de prêt encore active (rappel)
class ExchangesBadgeService {
  ExchangesBadgeService._();
  static final instance = ExchangesBadgeService._();

  static const _lastVisitKey = 'exchanges_hub_last_visit_ms';
  static const _loanWeekPrefix = 'exchanges_loan_week_';

  Future<int> computeBadgeCount({
    required List<CollectionItem> loans,
    required int duplicatesCount,
    required int forSaleCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastVisitKey);
    final lastVisit = lastMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastMs);
    final now = DateTime.now();
    var count = 0;

    for (final loan in loans) {
      final at = loan.loanedAt;
      if (at != null && (lastVisit == null || at.isAfter(lastVisit))) {
        count++;
        continue;
      }
      if (at == null) {
        if (lastVisit == null) count++;
        continue;
      }
      final weeks = now.difference(at).inDays ~/ 7;
      if (weeks <= 0) continue;
      final prev = prefs.getInt('$_loanWeekPrefix${loan.id}') ?? 0;
      if (weeks > prev) count++;
    }

    // Première ouverture : signaler qu'il y a du contenu dans le hub.
    if (lastVisit == null) {
      if (duplicatesCount > 0) count += duplicatesCount.clamp(0, 9);
      if (forSaleCount > 0) count += forSaleCount.clamp(0, 9);
    }

    return count;
  }

  Future<void> markVisited(List<CollectionItem> loans) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setInt(_lastVisitKey, now.millisecondsSinceEpoch);
    for (final loan in loans) {
      final at = loan.loanedAt;
      if (at == null) continue;
      final weeks = now.difference(at).inDays ~/ 7;
      await prefs.setInt('$_loanWeekPrefix${loan.id}', weeks);
    }
  }
}
