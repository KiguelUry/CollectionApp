import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/cover_image_url.dart';

/// Hôtes chargés en direct sur le web (<img> natif, sans proxy CORS).
const _directWebImageHosts = {
  'cf.geekdo-images.com',
  'boardgamegeek.com',
};

/// Hôtes / formats que le web charge mieux via <img> natif (CORS, AVIF…).
bool _preferWebHtmlImage(String url) {
  if (!kIsWeb) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (_directWebImageHosts.contains(host)) return true;
  if (path.endsWith('.avif')) return true;
  return host == 'cards.lorcast.io' ||
      host == 'www.optcgapi.com' ||
      host == 'images.ygoprodeck.com' ||
      host == 'assets.tcgdex.net';
}

/// Couverture nette (cache disque + mémoire, ratio livre, URLs adaptées).
class CollectionCoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool bookCover;
  /// Affiche l'image entière (jeux de société, boîtes…) sans rognage.
  final bool boxedCover;
  final bool largeSource;
  final Widget? placeholder;

  const CollectionCoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.bookCover = false,
    this.boxedCover = false,
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

    final padded = bookCover || boxedCover;
    final imageFit = padded ? BoxFit.contain : fit;
    Widget image;

    if (_preferWebHtmlImage(displayUrl)) {
      image = Image.network(
        displayUrl,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: FilterQuality.medium,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback(
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey.shade500,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => _fallback(),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: displayUrl,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: FilterQuality.medium,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        maxWidthDiskCache: cacheW,
        maxHeightDiskCache: cacheH,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
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
    }

    if (padded) {
      image = ColoredBox(
        color: Colors.grey.shade100,
        child: image,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(padded ? 6 : 8),
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
