import '../models/collection_item.dart';
import '../models/pokemon_card_lang.dart';
import '../models/tcg_set_info.dart';

/// Sous-titre compact sous le nom (bloc · série · n°/total).
String? tcgCatalogSubtitle(
  TcgCatalogCard card, {
  String? blockName,
  String? setName,
  int? setTotal,
}) {
  final block =
      blockName ?? card.raw['block_name'] ?? card.raw['series_name'];
  final set = setName ?? card.setName ?? card.raw['set_name'];
  final parts = <String>[];

  final blockTrim = block?.trim();
  final setTrim = set?.trim();
  if (blockTrim != null &&
      blockTrim.isNotEmpty &&
      blockTrim.toLowerCase() != (setTrim ?? '').toLowerCase()) {
    parts.add(blockTrim);
  }
  if (setTrim != null && setTrim.isNotEmpty) {
    parts.add(setTrim);
  }

  final num = card.number ?? card.raw['card_number'];
  final total = setTotal ?? int.tryParse(card.raw['set_total'] ?? '');
  if (num != null && num.trim().isNotEmpty) {
    parts.add(
      total != null && total > 0 ? '$num/$total' : num.trim(),
    );
  }

  return parts.isEmpty ? null : parts.join(' · ');
}

/// Sous-titre pour une carte en collection (bloc · série · n°/total).
String? tcgCollectionItemSubtitle(CollectionItem item) {
  final m = item.metadata;
  if (m == null) return null;

  final parts = <String>[];
  final lang = m['card_lang']?.toString();
  if (lang != null && lang.isNotEmpty) {
    parts.add(PokemonCardLang.shortLabel(lang));
  }
  final block = m['block_name'] ?? m['series_name'];
  final set = m['set_name'];
  final blockTrim = block?.toString().trim();
  final setTrim = set?.toString().trim();

  if (blockTrim != null &&
      blockTrim.isNotEmpty &&
      blockTrim.toLowerCase() != (setTrim ?? '').toLowerCase()) {
    parts.add(blockTrim);
  }
  if (setTrim != null && setTrim.isNotEmpty) {
    parts.add(setTrim);
  }

  final num = m['card_number'] ?? m['number'];
  final total = m['set_total'];
  if (num != null && num.toString().trim().isNotEmpty) {
    parts.add(
      total != null && total.toString().isNotEmpty
          ? '${num.toString().trim()}/${total.toString().trim()}'
          : num.toString().trim(),
    );
  }

  return parts.isEmpty ? null : parts.join(' · ');
}
