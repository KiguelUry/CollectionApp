import '../models/collection_item.dart';
import '../models/videogame_platform.dart';

List<String> videogamePlatformIdsFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?['platform_ids'];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  final single = metadata?['platform_id']?.toString();
  if (single != null && single.isNotEmpty) return [single];
  return VideogamePlatform.inferFromText(metadata?['platform']?.toString())
      .map((p) => p.id)
      .toList();
}

String videogamePlatformsLabel(Map<String, dynamic>? metadata) {
  final ids = videogamePlatformIdsFromMetadata(metadata);
  if (ids.isEmpty) {
    return metadata?['platform']?.toString() ?? '';
  }
  return ids
      .map((id) => VideogamePlatform.fromId(id)?.label ?? id)
      .join(', ');
}

int? videogameCompletionPercent(Map<String, dynamic>? metadata) {
  final raw = metadata?['completion_percent'];
  if (raw is int) return raw.clamp(0, 100);
  return int.tryParse(raw?.toString() ?? '')?.clamp(0, 100);
}

VideogamePlayStatus videogamePlayStatus(Map<String, dynamic>? metadata) {
  return VideogamePlayStatus.fromId(metadata?['play_status']?.toString());
}

double? videogameCommunityRating(Map<String, dynamic>? metadata) {
  return double.tryParse(metadata?['rawg_rating']?.toString() ?? '');
}

bool itemMatchesVideogamePlatform(
  Map<String, dynamic>? metadata,
  VideogamePlatform platform,
) {
  final ids = videogamePlatformIdsFromMetadata(metadata);
  if (ids.contains(platform.id)) return true;
  return VideogamePlatform.inferFromText(metadata?['platform']?.toString())
      .contains(platform);
}

List<VideogamePlatform> distinctVideogamePlatformsInCollection(
  List<CollectionItem> items,
) {
  final out = <VideogamePlatform>[];
  for (final item in items) {
    for (final id in videogamePlatformIdsFromMetadata(item.metadata)) {
      final p = VideogamePlatform.fromId(id);
      if (p != null && !out.contains(p)) out.add(p);
    }
  }
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}

Map<String, dynamic> metadataWithPlatforms(
  Map<String, dynamic>? metadata,
  List<VideogamePlatform> platforms,
) {
  final meta = Map<String, dynamic>.from(metadata ?? {});
  if (platforms.isEmpty) {
    meta.remove('platform_ids');
    return meta;
  }
  meta['platform_ids'] = platforms.map((p) => p.id).toList();
  meta['platform'] = platforms.map((p) => p.label).join(', ');
  return meta;
}
