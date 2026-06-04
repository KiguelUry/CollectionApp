import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/cover_image_url.dart';

/// Couverture nette (cache disque + mémoire, ratio livre, URLs adaptées).
class CollectionCoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool bookCover;
  final bool largeSource;
  final Widget? placeholder;

  const CollectionCoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.bookCover = false,
    this.largeSource = false,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final displayUrl = coverUrlForDisplay(url, large: largeSource);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = width;
    final h = height;
    final cacheW = _cachePixelSize(w, dpr);
    final cacheH = _cachePixelSize(h, dpr);

    Widget image = CachedNetworkImage(
      imageUrl: displayUrl,
      width: w,
      height: h,
      fit: bookCover ? BoxFit.contain : fit,
      filterQuality: FilterQuality.medium,
      memCacheWidth: cacheW,
      memCacheHeight: cacheH,
      maxWidthDiskCache: cacheW,
      maxHeightDiskCache: cacheH,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: (_, _) => _fallback(
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ),
      errorWidget: (_, _, _) => _fallback(),
    );

    if (bookCover && w != null && h != null) {
      image = ColoredBox(
        color: Colors.grey.shade100,
        child: image,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(bookCover ? 6 : 8),
      child: image,
    );
  }

  Widget _fallback({Widget? child}) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Colors.grey.shade200,
        child: child ??
            placeholder ??
            Center(
              child: Icon(
                bookCover ? Icons.menu_book_outlined : Icons.image_outlined,
                color: Colors.grey.shade500,
                size: (width != null && width!.isFinite && width! < 48)
                    ? 22
                    : 36,
              ),
            ),
      ),
    );
  }

  /// Évite cacheWidth/cacheHeight avec [double.infinity] → crash « infinity to int ».
  static int? _cachePixelSize(double? logicalPx, double dpr) {
    if (logicalPx == null || !logicalPx.isFinite || logicalPx <= 0) {
      return null;
    }
    return (logicalPx * dpr).round().clamp(1, 4096);
  }
}
