import '../models/collection_item.dart';

/// Option pour filtrer par « chez qui » (membre, nom libre, prêt).
class HolderFilterOption {
  const HolderFilterOption({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;
}

/// Clé stable pour filtrer / regrouper.
String? holderKeyForItem(CollectionItem item) {
  if (item.isOnLoan) {
    final name = item.loaneeDisplayName.trim();
    if (name.isNotEmpty) return 'loan:$name';
  }
  if (item.locationUserId != null && item.locationUserId!.isNotEmpty) {
    return 'user:${item.locationUserId}';
  }
  final custom = item.metadata?['holder_label'] as String?;
  if (custom != null && custom.trim().isNotEmpty) {
    return 'custom:${custom.trim().toLowerCase()}';
  }
  return null;
}

String holderLabelForItem(CollectionItem item) {
  if (item.isOnLoan) return 'Prêté → ${item.loaneeDisplayName}';
  final label = item.locationLabel?.trim();
  if (label != null && label.isNotEmpty && label != '—') {
    return label;
  }
  final custom = item.metadata?['holder_label'] as String?;
  if (custom != null && custom.trim().isNotEmpty) {
    final c = custom.trim();
    return c.toLowerCase().startsWith('chez ') ? c : 'Chez $c';
  }
  return 'Non renseigné';
}

List<HolderFilterOption> buildHolderFilterOptions(List<CollectionItem> items) {
  final counts = <String, ({String label, int n})>{};

  for (final item in items) {
    final key = holderKeyForItem(item);
    if (key == null) continue;
    final label = holderLabelForItem(item);
    final prev = counts[key];
    counts[key] = (label: label, n: (prev?.n ?? 0) + 1);
  }

  final list = counts.entries
      .map(
        (e) => HolderFilterOption(
          key: e.key,
          label: e.value.label,
          count: e.value.n,
        ),
      )
      .toList();
  list.sort((a, b) => b.count.compareTo(a.count));
  return list;
}

bool itemMatchesHolderKey(CollectionItem item, String? holderKey) {
  if (holderKey == null || holderKey.isEmpty) return true;
  return holderKeyForItem(item) == holderKey;
}
