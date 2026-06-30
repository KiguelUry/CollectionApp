import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Préfixe stocké dans `profiles.avatar_url` pour un avatar local.
const presetAvatarUrlPrefix = 'asset:';

const _presetExtensions = ['.svg', '.png', '.jpg', '.jpeg', '.webp'];

bool isPresetAvatarUrl(String? url) =>
    url != null && url.startsWith(presetAvatarUrlPrefix);

String? presetAvatarAssetPath(String? url) {
  if (!isPresetAvatarUrl(url)) return null;
  return url!.substring(presetAvatarUrlPrefix.length);
}

String presetAvatarUrl(String assetPath) => '$presetAvatarUrlPrefix$assetPath';

bool isPresetAvatarRaster(String assetPath) {
  final lower = assetPath.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp');
}

bool _isPresetAvatarAsset(String path) {
  if (!path.startsWith('assets/avatars/') || path.endsWith('/')) return false;
  final lower = path.toLowerCase();
  return _presetExtensions.any(lower.endsWith);
}

/// Liste les images déclarées sous `assets/avatars/` (SVG, PNG…).
Future<List<String>> discoverPresetAvatarAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final paths = manifest.listAssets().where(_isPresetAvatarAsset).toList()
    ..sort();
  return paths;
}

String presetAvatarLabel(String assetPath) {
  var name = assetPath.split('/').last;
  final lower = name.toLowerCase();
  for (final ext in _presetExtensions) {
    if (lower.endsWith(ext)) {
      name = name.substring(0, name.length - ext.length);
      break;
    }
  }
  return name
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
