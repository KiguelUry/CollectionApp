import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/cover_image_url.dart';

/// Couverture nette (cache mémoire, ratio livre, URLs OL en grande taille).
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

    Widget image = Image.network(
      displayUrl,
      width: w,
      height: h,
      fit: bookCover ? BoxFit.contain : fit,
      filterQuality: FilterQuality.medium,
      cacheWidth: cacheW,
      cacheHeight: cacheH,
      alignment: Alignment.center,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      errorBuilder: (_, _, _) => _fallback(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _fallback(
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
              ),
            ),
          ),
        );
      },
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
