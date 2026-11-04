import 'package:flutter/material.dart';

/// Coupe-circuit anti-boucle : une URL en échec n'est plus jamais redemandée.
final Set<String> kFailedImageUrls = <String>{};

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
    _failed = kFailedImageUrls.contains(widget.url);
  }

  @override
  void didUpdateWidget(covariant FailSafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _failed = kFailedImageUrls.contains(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed ||
        widget.url.isEmpty ||
        kFailedImageUrls.contains(widget.url)) {
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
        // Marque immédiatement (avant le prochain frame) pour bloquer tout retry.
        kFailedImageUrls.add(widget.url);
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
