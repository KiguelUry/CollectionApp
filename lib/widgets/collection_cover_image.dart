import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/cover_image_url.dart';
import 'fail_safe_network_image.dart';

export 'fail_safe_network_image.dart' show kFailedImageUrls;

/// Couverture nette (cache disque + mémoire, ratio livre, URLs adaptées).
///
/// Sur Flutter Web, les grilles utilisent [FailSafeNetworkImage]
/// pour éviter le crash de textures WebGL Firefox au scroll
/// et les boucles `requestAnimationFrame` sur CORS / 400.
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
            size: thumbSize.clamp(64, compact ? 300 : 600),
          )
        : url;

    if (kFailedImageUrls.contains(thumb) || kFailedImageUrls.contains(url)) {
      return _wrap(padded, _fallback());
    }

    Widget image;
    if (kIsWeb) {
      image = FailSafeNetworkImage(
        url: thumb,
        width: w,
        height: h,
        fit: imageFit,
        filterQuality: compact ? FilterQuality.low : FilterQuality.medium,
        gaplessPlayback: !compact,
        cacheWidth: compact ? kThumbnailSize : (largeSource ? 600 : 400),
        placeholder: (_) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback(
            child: Center(
              child: SizedBox(
                width: compact ? 18 : 22,
                height: compact ? 18 : 22,
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
        errorWidget: (context, failedUrl, _) {
          kFailedImageUrls.add(failedUrl);
          kFailedImageUrls.add(thumb);
          return _fallback();
        },
      );
    } else {
      image = _buildOriginal(context, imageFit);
    }

    return _wrap(padded, image);
  }

  Widget _wrap(bool padded, Widget image) {
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
    if (kFailedImageUrls.contains(displayUrl)) return _fallback();

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = width;
    final h = height;
    final cacheW = _cachePixelSize(w, dpr);
    final cacheH = _cachePixelSize(h, dpr);

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
      errorWidget: (_, failedUrl, _) {
        kFailedImageUrls.add(failedUrl);
        kFailedImageUrls.add(displayUrl);
        return _fallback();
      },
    );
  }

  Widget _fallback({Widget? child}) {
    return SizedBox(
      width: width,
      height: height,
      child: child != null
          ? ColoredBox(color: AppTheme.coverPlaceholderBg, child: child)
          : (placeholder ??
              CoverImagePlaceholder(
                bookCover: bookCover,
                width: width,
                height: height,
              )),
    );
  }

  static int? _cachePixelSize(double? logicalPx, double dpr) {
    if (logicalPx == null || !logicalPx.isFinite || logicalPx <= 0) {
      return null;
    }
    return (logicalPx * dpr).round().clamp(1, 4096);
  }
}

/// Placeholder esthétique quand `image_url` est absente ou en échec.
class CoverImagePlaceholder extends StatelessWidget {
  final bool bookCover;
  final double? width;
  final double? height;

  const CoverImagePlaceholder({
    super.key,
    this.bookCover = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final compact = width != null && width!.isFinite && width! < 48;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: AppTheme.coverPlaceholderBg,
        child: Center(
          child: Icon(
            bookCover ? Icons.menu_book_outlined : Icons.image_not_supported,
            color: AppTheme.coverPlaceholderIcon,
            size: compact ? 22 : 36,
          ),
        ),
      ),
    );
  }
}
