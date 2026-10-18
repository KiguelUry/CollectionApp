import '../models/collection_item.dart';
import '../models/item_condition.dart';
import '../services/household_service.dart';
import 'holder_label_utils.dart';

const kCopyUnitsMetadataKey = 'copy_units';
const kPurchaseKindMetadataKey = 'purchase_kind';
const kPurchaseSourceMetadataKey = 'purchase_source';

enum PurchaseKind {
  neuf,
  occasion,
  cadeau;

  String get dbValue => switch (this) {
        PurchaseKind.neuf => 'new',
        PurchaseKind.occasion => 'used',
        PurchaseKind.cadeau => 'gift',
      };

  String get label => switch (this) {
        PurchaseKind.neuf => 'Neuf',
        PurchaseKind.occasion => 'Seconde main',
        PurchaseKind.cadeau => 'Cadeau',
      };

  static PurchaseKind? fromDb(String? raw) {
    return switch (raw) {
      'new' || 'neuf' => PurchaseKind.neuf,
      'used' || 'occasion' || 'secondhand' => PurchaseKind.occasion,
      'gift' || 'cadeau' => PurchaseKind.cadeau,
      _ => null,
    };
  }
}

const purchaseSourceSuggestions = [
  'Vinted',
  'Brocante',
  'Case Départ',
  'Le Zèbre à Pois',
  'Philibert',
  'Fnac',
  'Ami',
];

/// Un exemplaire physique (localisation, état, prix) quand [CollectionItem.quantity] > 1.
class ItemCopyUnit {
  const ItemCopyUnit({
    required this.index,
    this.label,
    this.locationUserId,
    this.locationLabel,
    this.holderLabel,
    this.purchasePrice,
    this.purchaseKind,
    this.purchaseSource,
    this.condition,
    this.groupIds = const [],
  });

  final List<String> groupIds;
  final int index;
  final String? label;
  final String? locationUserId;
  final String? locationLabel;
  final String? holderLabel;
  final double? purchasePrice;
  final PurchaseKind? purchaseKind;
  final String? purchaseSource;
  final ItemCondition? condition;

  String defaultLabel(int oneBased) =>
      label?.trim().isNotEmpty == true ? label!.trim() : 'Exemplaire $oneBased';

  ItemCopyUnit copyWith({
    String? label,
    String? locationUserId,
    String? locationLabel,
    String? holderLabel,
    double? purchasePrice,
    PurchaseKind? purchaseKind,
    String? purchaseSource,
    ItemCondition? condition,
    List<String>? groupIds,
    bool clearLocationUserId = false,
    bool clearHolder = false,
    bool clearPrice = false,
    bool clearPurchaseKind = false,
    bool clearPurchaseSource = false,
    bool clearCondition = false,
  }) {
    return ItemCopyUnit(
      index: index,
      label: label ?? this.label,
      locationUserId:
          clearLocationUserId ? null : (locationUserId ?? this.locationUserId),
      locationLabel:
          clearHolder ? null : (locationLabel ?? this.locationLabel),
      holderLabel: clearHolder ? null : (holderLabel ?? this.holderLabel),
      purchasePrice: clearPrice ? null : (purchasePrice ?? this.purchasePrice),
      purchaseKind:
          clearPurchaseKind ? null : (purchaseKind ?? this.purchaseKind),
      purchaseSource: clearPurchaseSource
          ? null
          : (purchaseSource ?? this.purchaseSource),
      condition: clearCondition ? null : (condition ?? this.condition),
      groupIds: groupIds ?? this.groupIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
      if (locationUserId != null && locationUserId!.isNotEmpty)
        'location_user_id': locationUserId,
      if (locationLabel != null && locationLabel!.trim().isNotEmpty)
        'location_label': locationLabel!.trim(),
      if (holderLabel != null && holderLabel!.trim().isNotEmpty)
        'holder_label': holderLabelStorageValue(
          formatManualHolderLabel(holderLabel!.trim()),
        ),
      if (purchasePrice != null) 'purchase_price': purchasePrice,
      if (purchaseKind != null) 'purchase_kind': purchaseKind!.dbValue,
      if (purchaseSource != null && purchaseSource!.trim().isNotEmpty)
        'purchase_source': purchaseSource!.trim(),
      if (condition != null) 'condition': condition!.dbValue,
      if (groupIds.isNotEmpty) 'group_ids': groupIds,
    };
  }

  static ItemCopyUnit fromJson(Map<String, dynamic> map, int fallbackIndex) {
    final idx = map['index'] is int
        ? map['index'] as int
        : int.tryParse('${map['index']}') ?? fallbackIndex;
    final priceRaw = map['purchase_price'];
    double? price;
    if (priceRaw is num) {
      price = priceRaw.toDouble();
    } else if (priceRaw is String) {
      price = double.tryParse(priceRaw.trim());
    }
    return ItemCopyUnit(
      index: idx,
      label: map['label']?.toString(),
      locationUserId: map['location_user_id']?.toString(),
      locationLabel: map['location_label']?.toString(),
      holderLabel: map['holder_label']?.toString(),
      purchasePrice: price,
      purchaseKind: PurchaseKind.fromDb(map['purchase_kind']?.toString()),
      purchaseSource: map['purchase_source']?.toString(),
      condition: ItemCondition.fromDbValue(map['condition']?.toString()),
      groupIds: [
        if (map['group_ids'] is List)
          for (final id in map['group_ids'] as List)
            if (id != null) id.toString(),
      ],
    );
  }
}

List<String> _itemGroupIds(CollectionItem item) {
  final ids = <String>{};
  if (item.groupId != null && item.groupId!.isNotEmpty) ids.add(item.groupId!);
  final extra = item.metadata?['group_ids'];
  if (extra is List) {
    for (final id in extra) {
      if (id != null) ids.add(id.toString());
    }
  }
  return ids.toList();
}

/// Groupes de l'objet = union des groupes de ses exemplaires.
Set<String> unionCopyGroupIds(List<ItemCopyUnit> units) => {
      for (final u in units) ...u.groupIds,
    };

int copyUnitCountForItem(CollectionItem item) {
  if (item.isWishlist || item.isSold) return 0;
  final q = item.quantity;
  return q < 1 ? 0 : q;
}

bool itemUsesCopyUnits(CollectionItem item) => copyUnitCountForItem(item) > 1;

List<ItemCopyUnit> readCopyUnits(CollectionItem item) {
  final count = copyUnitCountForItem(item);
  if (count <= 1) return const [];

  final raw = item.metadata?[kCopyUnitsMetadataKey];
  final parsed = <ItemCopyUnit>[];
  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is Map) {
        parsed.add(
          ItemCopyUnit.fromJson(Map<String, dynamic>.from(e), i),
        );
      }
    }
  }

  parsed.sort((a, b) => a.index.compareTo(b.index));
  final byIndex = {for (final u in parsed) u.index: u};

  final units = <ItemCopyUnit>[];
  for (var i = 0; i < count; i++) {
    if (byIndex.containsKey(i)) {
      units.add(byIndex[i]!);
      continue;
    }
    if (i == 0 && count > 1) {
      units.add(
        ItemCopyUnit(
          index: 0,
          locationUserId: item.locationUserId,
          locationLabel: item.locationLabel,
          holderLabel: item.metadata?['holder_label']?.toString(),
          purchasePrice: item.purchasePrice,
          condition: item.itemCondition,
          groupIds: _itemGroupIds(item),
        ),
      );
    } else {
      units.add(ItemCopyUnit(index: i));
    }
  }
  return units;
}

Map<String, dynamic> copyUnitsToMetadata(
  Map<String, dynamic>? base,
  List<ItemCopyUnit> units,
) {
  final meta = Map<String, dynamic>.from(base ?? {});
  if (units.isEmpty) {
    meta.remove(kCopyUnitsMetadataKey);
  } else {
    meta[kCopyUnitsMetadataKey] = units.map((u) => u.toJson()).toList();
  }
  return meta;
}

CollectionItem itemWithCopyUnits(CollectionItem item, List<ItemCopyUnit> units) {
  return item.copyWith(metadata: copyUnitsToMetadata(item.metadata, units));
}

/// Enregistre les exemplaires et aligne le partage de l'objet (`group_id`,
/// `metadata.group_ids`) sur l'union des groupes des exemplaires.
CollectionItem itemWithCopyUnitsAndGroups(
  CollectionItem item,
  List<ItemCopyUnit> units, {
  String? Function(String groupId)? groupName,
}) {
  final meta = copyUnitsToMetadata(item.metadata, units);
  final union = unionCopyGroupIds(units).toList();
  if (union.isEmpty) {
    meta.remove('group_ids');
    return item.copyWith(metadata: meta, clearGroup: true);
  }
  meta['group_ids'] = union;
  final first = union.first;
  return item.copyWith(
    metadata: meta,
    groupId: first,
    groupName: groupName?.call(first) ?? item.groupName,
  );
}

/// Prix d'achat par exemplaire à partir d'une ligne brute Supabase.
/// Sans `copy_units`, le prix de la ligne ne vaut que pour le 1er exemplaire
/// (cohérent avec l'UI qui l'attribue à « Exemplaire 1 »).
List<double?> copyPurchasePricesFromRow({
  required int quantity,
  required double? purchasePrice,
  required Map<String, dynamic>? metadata,
}) {
  final count = quantity < 1 ? 1 : quantity;
  if (count == 1) return [purchasePrice];
  final prices = List<double?>.filled(count, null);
  final raw = metadata?[kCopyUnitsMetadataKey];
  if (raw is List && raw.isNotEmpty) {
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is! Map) continue;
      final unit = ItemCopyUnit.fromJson(Map<String, dynamic>.from(e), i);
      if (unit.index >= 0 && unit.index < count) {
        prices[unit.index] = unit.purchasePrice;
      }
    }
    return prices;
  }
  prices[0] = purchasePrice;
  return prices;
}

/// Aligne `copy_units` avec [CollectionItem.quantity] (après +/- exemplaire).
CollectionItem syncCopyUnitsQuantity(CollectionItem item) {
  final count = copyUnitCountForItem(item);
  if (count <= 1) {
    final meta = Map<String, dynamic>.from(item.metadata ?? {});
    meta.remove(kCopyUnitsMetadataKey);
    return item.copyWith(metadata: meta);
  }
  final units = readCopyUnits(item);
  final trimmed = units.take(count).toList();
  while (trimmed.length < count) {
    trimmed.add(ItemCopyUnit(index: trimmed.length));
  }
  return itemWithCopyUnits(item, trimmed);
}

/// Clé filtre pour un exemplaire (même logique que [holderKeyForItem]).
String? holderKeyForCopyUnit(ItemCopyUnit unit, {required bool itemOnLoan}) {
  if (itemOnLoan) return null;
  final shown = holderLabelForCopyUnit(unit);
  final home = HouseholdService.instance.matchLabel(shown);
  if (home != null) return 'home:${home.id}';
  if (unit.locationUserId != null && unit.locationUserId!.isNotEmpty) {
    return 'user:${unit.locationUserId}';
  }
  final custom = unit.holderLabel?.trim();
  if (custom != null && custom.isNotEmpty) {
    return 'custom:${custom.toLowerCase()}';
  }
  final label = unit.locationLabel?.trim();
  if (label != null && label.isNotEmpty && label != '—') {
    return 'custom:${label.toLowerCase()}';
  }
  return null;
}

String holderLabelForCopyUnit(ItemCopyUnit unit) {
  final raw = _rawCopyHolderLabel(unit);
  final home = HouseholdService.instance.matchLabel(raw);
  if (home != null) {
    return HouseholdService.instance.displayFor(home, rawLabel: raw);
  }
  return raw;
}

String _rawCopyHolderLabel(ItemCopyUnit unit) {
  if (unit.locationUserId != null && unit.locationUserId!.isNotEmpty) {
    final label = unit.locationLabel?.trim();
    if (label != null && label.isNotEmpty && label != '—') return label;
    return 'Membre';
  }
  final custom = unit.holderLabel?.trim();
  if (custom != null && custom.isNotEmpty) {
    return formatManualHolderLabel(custom);
  }
  final label = unit.locationLabel?.trim();
  if (label != null && label.isNotEmpty && label != '—') return label;
  return 'Non renseigné';
}

/// Libellé court pour le bento « Localisation » (priorité : chez moi).
String quickWhereaboutsSummaryLabel(
  CollectionItem item, {
  String? meUserId,
  String? meDisplayName,
}) {
  if (item.isOnLoan) {
    return 'Prêté → ${item.loaneeDisplayName}';
  }
  final count = copyUnitCountForItem(item);
  if (count > 1) {
    final units = readCopyUnits(item);
    ItemCopyUnit? mine;
    for (final u in units) {
      if (meUserId != null &&
          u.locationUserId != null &&
          u.locationUserId == meUserId) {
        mine = u;
        break;
      }
    }
    final pick = mine ?? units.firstWhere(
      (u) => holderKeyForCopyUnit(u, itemOnLoan: false) != null,
      orElse: () => units.first,
    );
    return _prefixChez(holderLabelForCopyUnit(pick), meUserId: meUserId);
  }

  if (item.locationUserId != null &&
      item.locationUserId!.isNotEmpty &&
      meUserId != null &&
      item.locationUserId == meUserId) {
    final name = meDisplayName?.trim();
    if (name != null && name.isNotEmpty) return 'Chez $name';
    return 'Chez moi';
  }
  final manual = item.metadata?['holder_label']?.toString().trim();
  if (manual != null && manual.isNotEmpty) {
    return _prefixChez(formatManualHolderLabel(manual), meUserId: meUserId);
  }
  final loc = item.locationLabel?.trim();
  if (loc != null && loc.isNotEmpty && loc != '—') {
    return _prefixChez(loc, meUserId: meUserId);
  }
  if (meDisplayName != null && meDisplayName.trim().isNotEmpty) {
    return 'Chez ${meDisplayName.trim()}';
  }
  return 'Chez moi';
}

String _prefixChez(String label, {String? meUserId}) {
  final t = label.trim();
  if (t.isEmpty) return 'Chez moi';
  final lower = t.toLowerCase();
  if (lower.startsWith('chez ') || lower.startsWith('à ')) return t;
  return 'Chez $t';
}
