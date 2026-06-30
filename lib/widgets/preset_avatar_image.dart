import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/preset_avatars.dart';

/// Affiche un avatar preset (SVG ou image raster).
class PresetAvatarImage extends StatelessWidget {
  final String assetPath;
  final BoxFit fit;

  const PresetAvatarImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (isPresetAvatarRaster(assetPath)) {
      return Image.asset(assetPath, fit: fit);
    }
    return SvgPicture.asset(assetPath, fit: fit);
  }
}
