import '../models/collection_item.dart';

/// Nombre de groupes auxquels l'objet appartient (metadata, group_id, contexte écran).
int groupMembershipCount(
  CollectionItem item, {
  String? contextGroupId,
}) {
  final extra = item.metadata?['group_ids'];
  if (extra is List && extra.isNotEmpty) {
    return extra.map((e) => e.toString()).where((s) => s.isNotEmpty).length;
  }
  if (item.groupId != null && item.groupId!.isNotEmpty) return 1;
  if (contextGroupId != null && contextGroupId.isNotEmpty) return 1;
  return 0;
}
