import 'package:flutter/material.dart';

import 'collection_cover_image.dart';

/// Images réseau (BGG, Open Library, etc.) avec rendu net.
class BggNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool bookCover;
  final bool largeSource;

  const BggNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.bookCover = false,
    this.largeSource = false,
  });

  @override
  Widget build(BuildContext context) {
    return CollectionCoverImage(
      url: url,
      width: width,
      height: height,
      fit: fit,
      bookCover: bookCover,
      largeSource: largeSource,
    );
  }
}
