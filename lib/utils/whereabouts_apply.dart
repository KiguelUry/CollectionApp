import '../models/collection_item.dart';
import 'holder_label_utils.dart';

/// Applique un changement « Chez qui ? » sur un [CollectionItem] en mémoire.
CollectionItem applyWhereaboutsChange(
  CollectionItem item, {
  String? locationUserId,
  String? holderLabel,
  bool clearHolder = false,
  bool manualHolder = false,
}) {
  final meta = Map<String, dynamic>.from(item.metadata ?? {});

  if (manualHolder) {
    final raw = holderLabel?.trim();
    final display =
        raw != null && raw.isNotEmpty ? formatManualHolderLabel(raw) : null;
    if (display != null) {
      meta['holder_label'] = holderLabelStorageValue(display);
    } else {
      meta.remove('holder_label');
    }
    return item.copyWith(
      clearLoan: true,
      clearLocationUserId: true,
      clearLocation: display == null,
      locationLabel: display,
      metadata: meta,
    );
  }

  if (clearHolder) {
    meta.remove('holder_label');
    return item.copyWith(
      clearLoan: true,
      clearLocationUserId: true,
      clearLocation: true,
      metadata: meta,
    );
  }

  meta.remove('holder_label');
  return item.copyWith(
    clearLoan: true,
    locationUserId: locationUserId,
    locationLabel: holderLabel,
    clearLocationUserId: locationUserId == null,
    metadata: meta,
  );
}

/// Payload metadata pour un exemplaire (holder_label vs membre).
Map<String, dynamic> whereaboutsMetadataForSave(CollectionItem item) {
  final meta = Map<String, dynamic>.from(item.metadata ?? {});
  if (item.locationUserId != null) {
    meta.remove('holder_label');
    return meta;
  }

  // Saisie libre : conserver holder_label existant en metadata en priorité.
  final stored = meta['holder_label']?.toString().trim();
  if (stored != null && stored.isNotEmpty) {
    meta['holder_label'] = holderLabelStorageValue(
      formatManualHolderLabel(stored),
    );
    return meta;
  }

  final label = item.locationLabel?.trim();
  if (label != null && label.isNotEmpty && label != '—') {
    meta['holder_label'] = holderLabelStorageValue(label);
  }
  return meta;
}
