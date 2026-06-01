import 'package:flutter/foundation.dart';

import '../models/card_subcategory.dart';
import '../models/tcg_set_info.dart';
import 'lorcast_service.dart';
import 'onepiece_tcg_service.dart';
import 'pokemon_tcg_service.dart';
import 'scryfall_service.dart';
import 'ygoprodeck_service.dart';

/// Recherche cartes selon l'univers — ne lève jamais d'exception.
class CardCatalogService {
  static bool supportsSearch(CardSubcategory sub) => sub.supportsCatalogSearch;

  static String catalogLabel(CardSubcategory sub) => switch (sub) {
        CardSubcategory.pokemon => 'TCGdex (FR)',
        CardSubcategory.magic => 'Scryfall',
        CardSubcategory.yugioh => 'YGOProDeck',
        CardSubcategory.onepiece => 'OPTCG API',
        CardSubcategory.lorcana => 'Lorcast',
        _ => 'saisie manuelle',
      };

  static Future<List<Map<String, String>>> search(
    String query, {
    required CardSubcategory subcategory,
  }) async {
    try {
      return await switch (subcategory) {
        CardSubcategory.pokemon => PokemonTcgService.search(query),
        CardSubcategory.magic => ScryfallService.search(query),
        CardSubcategory.yugioh => YgoprodeckService.search(query),
        CardSubcategory.onepiece => OnepieceTcgService.search(query),
        CardSubcategory.lorcana => LorcastService.search(query),
        _ => Future.value(<Map<String, String>>[]),
      };
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CardCatalogService.search($subcategory): $e\n$st');
      }
      return [];
    }
  }

  static Map<String, dynamic> metadataFromResult(
    Map<String, String> card,
    CardSubcategory subcategory,
  ) {
    return {
      'catalog_source': card['source'] ?? '',
      if ((card['set_name'] ?? '').isNotEmpty) 'set_name': card['set_name']!,
      if ((card['set_id'] ?? '').isNotEmpty) 'set_id': card['set_id']!,
      if ((card['set_code'] ?? '').isNotEmpty) 'set_code': card['set_code']!,
      if ((card['card_number'] ?? '').isNotEmpty)
        'card_number': card['card_number']!,
      if ((card['rarity'] ?? '').isNotEmpty) 'rarity': card['rarity']!,
      if ((card['scryfall_id'] ?? '').isNotEmpty)
        'scryfall_id': card['scryfall_id']!,
      if ((card['tcgdex_id'] ?? '').isNotEmpty) 'tcgdex_id': card['tcgdex_id']!,
      if ((card['pokemon_tcg_id'] ?? '').isNotEmpty)
        'pokemon_tcg_id': card['pokemon_tcg_id']!,
      if ((card['ygoprodeck_id'] ?? '').isNotEmpty)
        'ygoprodeck_id': card['ygoprodeck_id']!,
      if ((card['lorcast_id'] ?? '').isNotEmpty) 'lorcast_id': card['lorcast_id']!,
      if ((card['onepiece_card_id'] ?? '').isNotEmpty)
        'onepiece_card_id': card['onepiece_card_id']!,
      'card_universe': subcategory.dbValue,
    };
  }

  static Map<String, dynamic> metadataFromTcgCard(
    TcgCatalogCard card,
    CardSubcategory subcategory,
  ) {
    return {
      ...metadataFromResult(card.raw, subcategory),
      if (card.setName != null) 'set_name': card.setName!,
      if (card.number != null) 'card_number': card.number!,
      if (card.rarity != null) 'rarity': card.rarity!,
    };
  }
}
