import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Préfixe stocké dans `profiles.avatar_url` pour un avatar local.
const presetAvatarUrlPrefix = 'asset:';

const _presetExtensions = ['.svg', '.png', '.jpg', '.jpeg', '.webp'];

/// Libellés lisibles (sans IDs numériques).
const _avatarAliases = <String, String>{
  'america': 'Captain America',
  'avatar': 'Avatar',
  'bear': 'Ours',
  'butterfly': 'Papillon',
  'comic': 'Héros comic',
  'crab': 'Crabe',
  'dark': 'Dark',
  'deer': 'Cerf',
  'elephant': 'Éléphant',
  'fish': 'Poisson',
  'geek': 'Geek',
  'grandmother': 'Grand-mère',
  'head': 'Tête',
  'help': 'Aide',
  'hippo': 'Hippopotame',
  'hipster': 'Hipster',
  'kangaroo': 'Kangourou',
  'koala': 'Koala',
  'ladybug': 'Coccinelle',
  'light saber': 'Sabre laser',
  'lion': 'Lion',
  'man': 'Homme',
  'mask': 'Masque',
  'panda': 'Panda',
  'penguin': 'Pingouin',
  'polar bear': 'Ours polaire',
  'priest': 'Prêtre',
  'profile': 'Profil',
  'rabbit': 'Lapin',
  'robot': 'Robot',
  'shield': 'Bouclier',
  'squid': 'Calamar',
  'student': 'Étudiant',
  'superhero': 'Super-héros',
  'superheroe': 'Super-héros',
  'turtle': 'Tortue',
  'user': 'Utilisateur',
  'villain': 'Méchant',
  'walrus': 'Morse',
  'woman': 'Femme',
  'zebra': 'Zèbre',
};

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

String _stemKey(String assetPath) {
  var name = assetPath.split('/').last.toLowerCase();
  for (final ext in _presetExtensions) {
    if (name.endsWith(ext)) {
      name = name.substring(0, name.length - ext.length);
      break;
    }
  }
  // villain_1377103(1) → villain
  name = name.replaceAll(RegExp(r'[\(\)]'), '');
  name = name.replaceAll(RegExp(r'[_\-\s]+\d+$'), '');
  name = name.replaceAll(RegExp(r'\d+'), '');
  name = name.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return name;
}

/// Liste les images sous `assets/avatars/` (dédupliquées).
Future<List<String>> discoverPresetAvatarAssets() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final paths = manifest.listAssets().where(_isPresetAvatarAsset).toList()
    ..sort();
  final seen = <String>{};
  final unique = <String>[];
  for (final path in paths) {
    final key = _stemKey(path);
    // Garde la 1ère variante d’un même personnage (évite doubles villain).
    if (seen.add('$key|${path.split('.').last}')) {
      // Dedup stricter: same stem regardless of extension preference PNG over SVG
      final stemOnly = key;
      if (unique.any((p) => _stemKey(p) == stemOnly)) continue;
      unique.add(path);
    }
  }
  unique.sort((a, b) => presetAvatarLabel(a).compareTo(presetAvatarLabel(b)));
  return unique;
}

String presetAvatarLabel(String assetPath) {
  final stem = _stemKey(assetPath);
  if (stem.isEmpty) return 'Avatar';
  final alias = _avatarAliases[stem];
  if (alias != null) return alias;

  return stem
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
