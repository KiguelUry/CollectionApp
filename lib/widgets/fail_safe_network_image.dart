import 'package:flutter/material.dart';

/// Coupe-circuit anti-boucle : URL en échec non redemandée pendant un TTL.
/// Les 502 MangaDex/proxy sont souvent transitoires (rafale) → TTL court.
final Map<String, DateTime> _failedUntil = <String, DateTime>{};

const _kHardFailTtl = Duration(hours: 6);
const _kSoftFailTtl = Duration(seconds: 45);

void markImageUrlFailed(String url, {bool soft = false}) {
  _failedUntil[url] = DateTime.now().add(soft ? _kSoftFailTtl : _kHardFailTtl);
}

bool isImageUrlFailed(String url) {
  final until = _failedUntil[url];
  if (until == null) return false;
  if (DateTime.now().isAfter(until)) {
    _failedUntil.remove(url);
    return false;
  }
  return true;
}

/// Compat historique : API [Set]-like pour les checks existants.
final kFailedImageUrls = _FailedUrlFacade();

class _FailedUrlFacade {
  bool contains(Object? element) {
    if (element is! String) return false;
    return isImageUrlFailed(element);
  }

  bool add(String value) {
    markImageUrlFailed(value, soft: false);
    return true;
  }

  void clear() => _failedUntil.clear();
}

/// [Image.network] avec coupe-circuit : dès le 1er échec, plus aucun
/// `ImageProvider` / XHR aux frames suivantes (fini le spam CanvasKit).
class FailSafeNetworkImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget Function(BuildContext context) placeholder;
  final Widget Function(
    BuildContext context,
    Widget child,
    ImageChunkEvent? progress,
  )? loadingBuilder;

  const FailSafeNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.low,
    this.gaplessPlayback = false,
    this.cacheWidth,
    this.cacheHeight,
    this.loadingBuilder,
  });

  @override
  State<FailSafeNetworkImage> createState() => _FailSafeNetworkImageState();
}

class _FailSafeNetworkImageState extends State<FailSafeNetworkImage> {
  late bool _failed;

  @override
  void initState() {
    super.initState();
    _failed = isImageUrlFailed(widget.url);
  }

  @override
  void didUpdateWidget(covariant FailSafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _failed = isImageUrlFailed(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.url.isEmpty || isImageUrlFailed(widget.url)) {
      return widget.placeholder(context);
    }

    return Image.network(
      widget.url,
      key: ValueKey('img-${widget.url}'),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      gaplessPlayback: widget.gaplessPlayback,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      errorBuilder: (_, _, _) {
        // Soft : laisse réessayer après 45s (502 proxy / rate-limit).
        markImageUrlFailed(widget.url, soft: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_failed) setState(() => _failed = true);
        });
        return widget.placeholder(context);
      },
      loadingBuilder: widget.loadingBuilder == null
          ? null
          : (context, child, progress) =>
              widget.loadingBuilder!(context, child, progress),
    );
  }
}
