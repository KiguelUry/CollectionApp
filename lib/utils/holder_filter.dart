import '../models/collection_item.dart';
import '../services/household_service.dart';
import 'holder_label_utils.dart';
import 'item_copy_units.dart';

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

String? _withHousehold(String? key, String label) {
  final home = HouseholdService.instance.matchLabel(label);
  if (home == null) return key;
  return 'home:${home.id}';
}

/// Clé stable pour filtrer / regrouper.
String? holderKeyForItem(CollectionItem item) {
  if (item.isOnLoan) {
    final name = item.loaneeDisplayName.trim();
    if (name.isNotEmpty) return 'loan:$name';
  }
  if (item.locationUserId != null && item.locationUserId!.isNotEmpty) {
    final label = item.locationLabel?.trim();
    final shown = (label != null && label.isNotEmpty && label != '—')
        ? label
        : 'Membre';
    return _withHousehold('user:${item.locationUserId}', shown);
  }
  final custom = item.metadata?['holder_label'] as String?;
  if (custom != null && custom.trim().isNotEmpty) {
    final shown = formatManualHolderLabel(custom.trim());
    return _withHousehold('custom:${custom.trim().toLowerCase()}', shown);
  }
  if (item.locationId != null && item.locationId!.isNotEmpty) {
    return 'loc:${item.locationId}';
  }
  return null;
}

String holderLabelForItem(CollectionItem item) {
  if (item.isOnLoan) return 'Prêté → ${item.loaneeDisplayName}';
  final raw = _rawHolderLabel(item);
  final home = HouseholdService.instance.matchLabel(raw);
  if (home != null) {
    return HouseholdService.instance.displayFor(home, rawLabel: raw);
  }
  return raw;
}

String _rawHolderLabel(CollectionItem item) {
  if (item.locationUserId != null && item.locationUserId!.isNotEmpty) {
    final label = item.locationLabel?.trim();
    if (label != null && label.isNotEmpty && label != '—') return label;
    return 'Membre';
  }
  final custom = item.metadata?['holder_label'] as String?;
  if (custom != null && custom.trim().isNotEmpty) {
    return formatManualHolderLabel(custom.trim());
  }
  final label = item.locationLabel?.trim();
  if (label != null && label.isNotEmpty && label != '—') {
    return label;
  }
  return 'Non renseigné';
}

Iterable<({String key, String label})> _holderEntriesForItem(
  CollectionItem item,
) sync* {
  if (itemUsesCopyUnits(item)) {
    for (final unit in readCopyUnits(item)) {
      final key = holderKeyForCopyUnit(unit, itemOnLoan: item.isOnLoan);
      if (key == null) continue;
      yield (key: key, label: holderLabelForCopyUnit(unit));
    }
    return;
  }
  final key = holderKeyForItem(item);
  if (key == null) return;
  yield (key: key, label: holderLabelForItem(item));
}

List<HolderFilterOption> buildHolderFilterOptions(List<CollectionItem> items) {
  final counts = <String, ({String label, int n})>{};

  for (final item in items) {
    for (final entry in _holderEntriesForItem(item)) {
      final prev = counts[entry.key];
      counts[entry.key] = (label: entry.label, n: (prev?.n ?? 0) + 1);
    }
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
  for (final entry in _holderEntriesForItem(item)) {
    if (entry.key == holderKey) return true;
  }
  return false;
}
