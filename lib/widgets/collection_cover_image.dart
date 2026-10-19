import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
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
  /// Grille / liste : URL vignette + qualité réduite (web : garde <img> natif pour BGG).
  final bool compact;
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
    this.compact = false,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final padded = bookCover || boxedCover;
    final imageFit = padded ? BoxFit.contain : fit;
    final w = width;
    final h = height;

    Widget image;
    final thumbSize = compact ? kThumbnailSize : (largeSource ? 1000 : 600);
    final thumb = (compact || kIsWeb)
        ? gridThumbnailUrl(
            url,
            crop: !padded && fit == BoxFit.cover,
            size: thumbSize,
          )
        : url;
    if (thumb != url) {
      // Image décodée dans la case. Une balise <img> du navigateur se
      // repositionne mal et colle la jaquette d'un autre jeu sur le titre.
      image = CachedNetworkImage(
        key: ValueKey(thumb),
        imageUrl: thumb,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: compact ? FilterQuality.low : FilterQuality.medium,
        memCacheWidth: compact ? kThumbnailSize : null,
        memCacheHeight: compact ? kThumbnailSize : null,
        // Octets, pas une balise <img>. Flutter 3.47 (build GitHub Pages)
        // peint en noir les images HTML dès que le cache les lâche.
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: Duration.zero,
        placeholder: (_, _) => _fallback(child: const SizedBox.shrink()),
        errorWidget: (context, _, _) => _buildOriginal(context, imageFit),
      );
    } else {
      image = _buildOriginal(context, imageFit);
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

  Widget _buildOriginal(BuildContext context, BoxFit imageFit) {
    final displayUrl = coverUrlForDisplay(url, large: largeSource);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = width;
    final h = height;
    final cacheW = _cachePixelSize(w, dpr);
    final cacheH = _cachePixelSize(h, dpr);
    Widget image;

    if (_preferWebHtmlImage(displayUrl)) {
      final proxied = gridThumbnailUrl(
        displayUrl,
        size: largeSource ? 1000 : 600,
      );
      image = CachedNetworkImage(
        key: ValueKey(proxied),
        imageUrl: proxied,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: compact ? FilterQuality.low : FilterQuality.medium,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
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
    } else {
      image = CachedNetworkImage(
        imageUrl: displayUrl,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: compact ? FilterQuality.low : FilterQuality.medium,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
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
    return image;
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
