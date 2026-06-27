import '../models/collection_item.dart';
import 'whereabouts_apply.dart';
import 'holder_label_utils.dart';

/// Fusionne `group_ids` sans écraser le reste du metadata (dont `holder_label`).
Map<String, dynamic> metadataWithGroupIds(
  Map<String, dynamic>? metadata,
  List<String> groupIds,
) {
  final meta = Map<String, dynamic>.from(metadata ?? {});
  if (groupIds.isEmpty) {
    meta.remove('group_ids');
  } else {
    meta['group_ids'] = groupIds;
  }
  return meta;
}

/// Champs Supabase pour le lieu : membre (`location_user_id`) ou saisie libre (`holder_label`).
///
/// Règle unique, avec ou sans groupe :
/// - Membre/ami : `location_user_id` renseigné, `holder_label` retiré du metadata.
/// - Autre : `location_user_id` = null, texte dans `metadata.holder_label`.
Map<String, dynamic> buildWhereaboutsDbFields(
  CollectionItem item, {
  List<String>? groupIds,
}) {
  var working = item;
  if (groupIds != null) {
    working = item.copyWith(
      metadata: metadataWithGroupIds(item.metadata, groupIds),
    );
  }
  return {
    'location_user_id': working.locationUserId,
    'metadata': whereaboutsMetadataForSave(working),
  };
}

/// Fusionne un patch metadata en préservant explicitement `holder_label` si absent du patch.
Map<String, dynamic> mergeMetadataPreservingHolder(
  Map<String, dynamic>? existing,
  Map<String, dynamic> patch,
) {
  final merged = Map<String, dynamic>.from(existing ?? {});
  final preservedHolder = merged['holder_label'];
  merged.addAll(patch);
  if (!patch.containsKey('holder_label') &&
      preservedHolder != null &&
      preservedHolder.toString().trim().isNotEmpty) {
    merged['holder_label'] = preservedHolder;
  }
  return merged;
}

/// Force `holder_label` dans le payload si l'objet est en mode manuel.
Map<String, dynamic> finalizeMetadataPayload(
  CollectionItem item,
  Map<String, dynamic> metadata,
) {
  if (item.locationUserId != null) return metadata;
  final fromMeta = item.metadata?['holder_label']?.toString().trim();
  if (fromMeta != null && fromMeta.isNotEmpty) {
    metadata['holder_label'] = fromMeta;
    return metadata;
  }
  final fromLabel = item.locationLabel?.trim();
  if (fromLabel != null && fromLabel.isNotEmpty && fromLabel != '—') {
    metadata['holder_label'] = holderLabelStorageValue(fromLabel);
  }
  return metadata;
}

bool itemHasManualHolder(CollectionItem item) {
  if (item.locationUserId != null) return false;
  final meta = item.metadata?['holder_label']?.toString().trim();
  if (meta != null && meta.isNotEmpty) return true;
  final label = item.locationLabel?.trim();
  return label != null && label.isNotEmpty && label != '—';
}

/// Prépare le lieu avant insert/update : membre par défaut ou saisie libre « Autre ».
CollectionItem prepareItemWhereabouts(
  CollectionItem item, {
  required String defaultUserId,
  String? holderLabel,
  bool isWishlist = false,
}) {
  if (isWishlist) return item;
  if (holderLabel != null && holderLabel.trim().isNotEmpty) {
    return applyWhereaboutsChange(
      item,
      manualHolder: true,
      holderLabel: holderLabel,
    );
  }
  if (item.locationUserId != null) return item;
  return item.copyWith(locationUserId: defaultUserId);
}

/// Payload Supabase pour un nouvel objet (lieu + metadata cohérents).
Map<String, dynamic> buildCollectionItemInsertPayload({
  required CollectionItem item,
  required String addedBy,
  required bool isWishlist,
  String? holderLabel,
  required String defaultUserId,
}) {
  final draft = prepareItemWhereabouts(
    item,
    defaultUserId: defaultUserId,
    holderLabel: holderLabel,
    isWishlist: isWishlist,
  );
  final groupIds = item.groupId != null && item.groupId!.isNotEmpty
      ? [item.groupId!]
      : <String>[];
  var working = draft;
  if (groupIds.isNotEmpty) {
    working = draft.copyWith(
      metadata: metadataWithGroupIds(draft.metadata, groupIds),
    );
  }
  final whereabouts = buildWhereaboutsDbFields(
    working,
    groupIds: groupIds.isEmpty ? null : groupIds,
  );
  var meta = Map<String, dynamic>.from(
    whereabouts['metadata'] as Map<String, dynamic>,
  );
  meta = finalizeMetadataPayload(working, meta);
  final json = working.toInsertJson(
    isWishlist: isWishlist,
    locationUserId: whereabouts['location_user_id'] as String?,
    addedBy: addedBy,
  );
  json['metadata'] = meta;
  json['location_user_id'] = whereabouts['location_user_id'];
  return json;
}
