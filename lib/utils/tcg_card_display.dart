import '../models/tcg_set_info.dart';

/// Lignes d'info sous la vignette catalogue (bloc, série, numéro).
List<String> tcgCatalogDetailLines(
  TcgCatalogCard card, {
  String? blockName,
  String? setName,
  int? setTotal,
}) {
  final lines = <String>[];
  final block =
      blockName ?? card.raw['block_name'] ?? card.raw['series_name'];
  final set = setName ?? card.setName ?? card.raw['set_name'];
  if (block != null && block.trim().isNotEmpty) {
    lines.add('Bloc : ${block.trim()}');
  }
  if (set != null && set.trim().isNotEmpty) {
    lines.add('Série : ${set.trim()}');
  }
  final num = card.number ?? card.raw['card_number'];
  final total =
      setTotal ?? int.tryParse(card.raw['set_total'] ?? '');
  if (num != null && num.trim().isNotEmpty) {
    lines.add(
      total != null && total > 0 ? 'N° : $num/$total' : 'N° : $num',
    );
  }
  return lines;
}
