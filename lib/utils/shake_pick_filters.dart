import '../models/collection_item.dart';
import 'holder_filter.dart';

enum ShakePickDuration {
  any,
  quick,
  medium,
  long,
}

class ShakePickFilters {
  final int? playerCount;
  final ShakePickDuration duration;
  /// Clé filtre localisation (`holderKeyForItem` / `custom:…` / user id).
  final String? holderKey;

  const ShakePickFilters({
    this.playerCount,
    this.duration = ShakePickDuration.any,
    this.holderKey,
  });

  bool get hasActive =>
      playerCount != null ||
      duration != ShakePickDuration.any ||
      (holderKey != null && holderKey!.isNotEmpty);

  bool matches(CollectionItem item) {
    if (playerCount != null) {
      final n = playerCount!;
      final minP = item.minPlayers;
      final maxP = item.maxPlayers ?? item.minPlayers;
      if (minP != null && n < minP) return false;
      if (maxP != null && n > maxP) return false;
      if (minP == null && maxP == null) return false;
    }

    final time = item.playingTime;
    if (duration != ShakePickDuration.any) {
      if (time == null || time <= 0) return false;
      switch (duration) {
        case ShakePickDuration.quick:
          if (time >= 30) return false;
        case ShakePickDuration.medium:
          if (time < 30 || time > 60) return false;
        case ShakePickDuration.long:
          if (time <= 60) return false;
        case ShakePickDuration.any:
          break;
      }
    }

    if (holderKey != null && holderKey!.isNotEmpty) {
      if (!itemMatchesHolderKey(item, holderKey)) return false;
    }

    return true;
  }
}
