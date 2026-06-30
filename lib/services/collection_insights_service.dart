import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_insight.dart';
import '../services/tcg_completion_service.dart';
import '../utils/collection_item_scope.dart';
import '../utils/tech_warranty.dart';

/// Alertes utiles agrégées depuis la collection (une passe DB).
class CollectionInsightsService {
  final _client = Supabase.instance.client;
  final _tcg = TcgCompletionService();

  Future<List<CollectionInsight>> fetch({int limit = 4}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final insights = <CollectionInsight>[];

    final rows = await CollectionItemScope.personal(
      _client.from('collection_items').select(
        'category, title, metadata, loaned_to_id, loaned_to_name, loaned_at',
      ),
      userId: userId,
    );

    var warrantySoon = 0;
    var warrantyExpired = 0;
    var oldLoans = 0;
    final now = DateTime.now();

    for (final raw in rows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      final cat = CollectionCategory.fromDbValue(
        map['category']?.toString() ?? '',
      );

      if (cat == CollectionCategory.tech) {
        final meta = map['metadata'] as Map<String, dynamic>?;
        final end = meta?['warranty_end']?.toString();
        switch (warrantyStatus(end)) {
          case TechWarrantyStatus.expired:
            warrantyExpired++;
          case TechWarrantyStatus.soon:
            warrantySoon++;
          case TechWarrantyStatus.valid:
          case TechWarrantyStatus.unknown:
            break;
        }
      }

      final loanedTo = map['loaned_to_id'] ?? map['loaned_to_name'];
      if (loanedTo != null && loanedTo.toString().isNotEmpty) {
        final atRaw = map['loaned_at']?.toString();
        final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
        if (at != null && now.difference(at).inDays >= 30) {
          oldLoans++;
        }
      }
    }

    if (warrantyExpired > 0) {
      insights.add(
        CollectionInsight(
          kind: CollectionInsightKind.warranty,
          message: warrantyExpired == 1
              ? '1 garantie high-tech expirée'
              : '$warrantyExpired garanties high-tech expirées',
          actionLabel: 'High-Tech',
        ),
      );
    } else if (warrantySoon > 0) {
      insights.add(
        CollectionInsight(
          kind: CollectionInsightKind.warranty,
          message: warrantySoon == 1
              ? '1 garantie expire dans les 30 jours'
              : '$warrantySoon garanties expirent bientôt',
          actionLabel: 'High-Tech',
        ),
      );
    }

    if (oldLoans > 0) {
      insights.add(
        CollectionInsight(
          kind: CollectionInsightKind.loan,
          message: oldLoans == 1
              ? '1 prêt en cours depuis plus de 30 jours'
              : '$oldLoans prêts en cours depuis plus de 30 jours',
          actionLabel: 'Prêts',
        ),
      );
    }

    final stats = await _tcg.fetchSubcategoryStats();
    final tcgTotal = stats.fold<int>(0, (sum, s) => sum + s.ownedCards);
    if (tcgTotal > 0) {
      final best = stats.where((s) => s.setsTouched > 0).toList()
        ..sort((a, b) => b.ownedCards.compareTo(a.ownedCards));
      if (best.isNotEmpty) {
        final top = best.first;
        insights.add(
          CollectionInsight(
            kind: CollectionInsightKind.tcg,
            message:
                '$tcgTotal cartes TCG — le plus actif : ${top.subcategory.label}',
            actionLabel: 'Complétion',
          ),
        );
      }
    }

    return insights.take(limit).toList();
  }
}
