import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/cover_image_url.dart';

/// Couverture nette (cache disque + mémoire, ratio livre, URLs adaptées).
///
/// Sur Flutter Web, les grilles utilisent [Image.network] (pas CachedNetworkImage)
/// pour éviter le crash de textures WebGL Firefox au scroll
/// (`tex(Sub)Image… Resource has no data`).
class CollectionCoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool bookCover;
  /// Affiche l'image entière (jeux de société, boîtes…) sans rognage.
  final bool boxedCover;
  final bool largeSource;
  /// Grille / liste : URL vignette + qualité réduite.
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

    final thumbSize = compact ? kThumbnailSize : (largeSource ? 1000 : 600);
    final thumb = (compact || kIsWeb)
        ? gridThumbnailUrl(
            url,
            crop: !padded && fit == BoxFit.cover,
            size: thumbSize,
          )
        : url;

    Widget image;
    if (kIsWeb && compact) {
      // Image.network charge dès le build (pas de keepAlive / RepaintBoundary).
      image = Image.network(
        thumb,
        key: ValueKey(thumb),
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        cacheWidth: kThumbnailSize,
        errorBuilder: (_, _, _) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback(
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          );
        },
      );
    } else if (thumb != url) {
      image = CachedNetworkImage(
        key: ValueKey(thumb),
        imageUrl: thumb,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: compact ? FilterQuality.low : FilterQuality.medium,
        memCacheWidth: compact ? kThumbnailSize : null,
        memCacheHeight: compact ? kThumbnailSize : null,
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

    if (kIsWeb) {
      final proxied = gridThumbnailUrl(
        displayUrl,
        size: largeSource ? 1000 : 600,
      );
      return Image.network(
        proxied,
        key: ValueKey(proxied),
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: compact ? FilterQuality.low : FilterQuality.medium,
        gaplessPlayback: true,
        cacheWidth: largeSource ? 1000 : 600,
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
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          );
        },
      );
    }

    return CachedNetworkImage(
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

  static int? _cachePixelSize(double? logicalPx, double dpr) {
    if (logicalPx == null || !logicalPx.isFinite || logicalPx <= 0) {
      return null;
    }
    return (logicalPx * dpr).round().clamp(1, 4096);
  }
}
