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

/// Vrai si l'objet est ailleurs que « Chez moi » (membre, ami ou lieu libre).
bool isAwayFromHome(CollectionItem item, {String? meUserId}) {
  final holder = item.locationUserId;
  if (holder != null && holder.isNotEmpty) {
    return meUserId != null && holder != meUserId;
  }
  final manual = (item.metadata?['holder_label']?.toString() ??
          item.locationLabel ??
          '')
      .trim();
  if (manual.isEmpty || manual == '—') return false;
  return manual.toLowerCase() != 'chez moi';
}

/// Nom de l'emprunteur déduit du lieu (« Chez Lou » → « Lou »).
String? loaneeNameFromWhereabouts(CollectionItem item) {
  final raw = (item.locationLabel ??
          item.metadata?['holder_label']?.toString() ??
          '')
      .trim();
  if (raw.isEmpty || raw == '—') return null;
  final plain = holderLabelStorageValue(raw).trim();
  return plain.isEmpty ? null : plain;
}

/// Active / coupe le « prêt temporaire ».
///
/// Le lieu (« Braine-l'Alleud », etc.) n'est **pas** recopié dans « Prêté à » :
/// l'emprunteur est fourni explicitement ([borrowerName] / [borrowerId]).
CollectionItem applyTemporaryLoan(
  CollectionItem item, {
  required bool isLoan,
  DateTime? loanedAt,
  String? meUserId,
  String? borrowerName,
  String? borrowerId,
}) {
  if (!isLoan) return item.copyWith(clearLoan: true);
  final name = borrowerName?.trim();
  final explicitName = name != null && name.isNotEmpty ? name : null;
  // Mise à jour date seule : conserver l'emprunteur déjà saisi.
  final keepName = explicitName ?? item.loanedToName;
  final keepId = borrowerId ?? item.loanedToId;
  return item.copyWith(clearLoan: true).copyWith(
        loanedToId: keepId,
        loanedToName: keepName,
        loanedAt: loanedAt ?? item.loanedAt ?? DateTime.now(),
      );
}

/// Colonnes Supabase du prêt (null = pas de prêt).
Map<String, dynamic> loanDbFields(CollectionItem item) => {
      'loaned_to_id': item.loanedToId,
      'loaned_to_name': item.loanedToName,
      'loaned_at': item.loanedAt?.toUtc().toIso8601String(),
    };

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
