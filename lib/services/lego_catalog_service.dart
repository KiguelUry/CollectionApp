import 'lego_fandom_service.dart';
import 'rebrickable_service.dart';

/// Lego & maquettes — Rebrickable si clé, sinon wiki Lego (gratuit).
class LegoCatalogService {
  static bool get rebrickableEnabled => RebrickableService.isConfigured;

  static String get catalogLabel {
    if (rebrickableEnabled) {
      return 'Rebrickable · secours wiki Lego sans clé';
    }
    return 'Wiki Lego (gratuit, sans clé API)';
  }

  static Future<List<Map<String, String>>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    if (rebrickableEnabled) {
      final rb = await RebrickableService.search(q);
      if (rb.isNotEmpty) return rb;

      final setNum = RegExp(r'^\d{4,7}$').hasMatch(q);
      if (setNum) {
        final one = await RebrickableService.lookupSetNumber(q);
        if (one != null) return [one];
      }
    }

    return LegoFandomService.search(q);
  }
}
