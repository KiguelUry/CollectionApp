import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bgg_service.dart';
import '../utils/cover_image_url.dart';
import '../utils/platform_input.dart';
import 'collection_cover_image.dart';

/// Bande de miniatures BGG : défilement souris et flèches, lightbox HD.
class BggPhotoStrip extends StatefulWidget {
  final List<BggGalleryPhoto> photos;

  const BggPhotoStrip({super.key, required this.photos});

  @override
  State<BggPhotoStrip> createState() => _BggPhotoStripState();
}

class _BggPhotoStripState extends State<BggPhotoStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nudge(double delta) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          _Arrow(
            icon: Icons.chevron_left,
            tooltip: 'Photos précédentes',
            onPressed: () => _nudge(-280),
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: widget.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final photo = widget.photos[i];
                  return GestureDetector(
                    onTap: () => showBggPhotoLightbox(context, widget.photos, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 128,
                        child: CollectionCoverImage(
                          key: ValueKey(photo.url),
                          url: bggMaterialPhotoUrl(photo.url),
                          width: 128,
                          height: 96,
                          fit: BoxFit.cover,
                          compact: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          _Arrow(
            icon: Icons.chevron_right,
            tooltip: 'Photos suivantes',
            onPressed: () => _nudge(280),
          ),
        ],
      ),
    );
  }
}

/// Au-delà de ce facteur, la photo est « zoomée » : le swipe entre photos
/// est coupé pour laisser le pan à l'[InteractiveViewer].
const kLightboxZoomedScale = 1.05;
const kLightboxDoubleTapScale = 2.5;

/// Matrice de zoom ×[scale] centrée sur [focal] (coordonnées du viewport).
Matrix4 zoomAtPoint(Offset focal, double scale) {
  return Matrix4.identity()
    ..translateByDouble(
      -focal.dx * (scale - 1),
      -focal.dy * (scale - 1),
      0,
      1,
    )
    ..scaleByDouble(scale, scale, 1, 1);
}

class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onSingleTap;

  const _ZoomablePhoto({
    super.key,
    required this.url,
    required this.onZoomChanged,
    required this.onSingleTap,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _tween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final t = _tween;
        if (t != null) _transform.value = t.value;
      });
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _anim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > kLightboxZoomedScale;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  void _toggleZoom() {
    final target = _zoomed
        ? Matrix4.identity()
        : zoomAtPoint(_doubleTapAt, kLightboxDoubleTapScale);
    _tween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSingleTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: SizedBox.expand(
        child: InteractiveViewer(
          transformationController: _transform,
          clipBehavior: Clip.none,
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                );
              },
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

/// Visionneuse plein écran noire : pinch / double-tap pour zoomer, swipe
/// entre photos (désactivé pendant le zoom), ✕ + compteur + légende.
Future<void> showBggPhotoLightbox(
  BuildContext context,
  List<BggGalleryPhoto> photos,
  int initialIndex,
) {
  if (photos.isEmpty) return Future.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) =>
        BggPhotoLightbox(photos: photos, initialIndex: initialIndex),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class BggPhotoLightbox extends StatefulWidget {
  final List<BggGalleryPhoto> photos;
  final int initialIndex;

  const BggPhotoLightbox({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<BggPhotoLightbox> createState() => _BggPhotoLightboxState();
}

class _BggPhotoLightboxState extends State<BggPhotoLightbox> {
  late final PageController _page;
  late int _index;
  bool _zoomed = false;
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.photos.length - 1);
    if (next == _index) return;
    _page.animateToPage(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final caption = photo.caption.trim();
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 700;
    final total = widget.photos.length;
    // Sur PC : photo à ~80 % avec marge noire confortable.
    final framed = wide;

    return Focus(
      autofocus: kSafeAutofocus,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Clic sur le fond noir (hors image, non zoomé) → fermer.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _zoomed ? null : () => Navigator.pop(context),
              ),
            ),
            Center(
              child: SizedBox(
                width: framed ? size.width * 0.8 : size.width,
                height: framed ? size.height * 0.8 : size.height,
                child: GestureDetector(
                  onTap: () {}, // absorbe le tap pour ne pas fermer
                  child: PageView.builder(
                    key: const ValueKey('lightbox_pages'),
                    controller: _page,
                    itemCount: total,
                    physics: _zoomed
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: (value) => setState(() {
                      _index = value;
                      _zoomed = false;
                    }),
                    itemBuilder: (context, i) => _ZoomablePhoto(
                      key: ValueKey(widget.photos[i].url),
                      url: bggMaterialPhotoUrl(
                        widget.photos[i].url,
                        width: 1400,
                        quality: 90,
                      ),
                      onZoomChanged: (z) {
                        if (mounted && z != _zoomed) {
                          setState(() => _zoomed = z);
                        }
                      },
                      onSingleTap: () => setState(() => _chrome = !_chrome),
                    ),
                  ),
                ),
              ),
            ),
            _fade(
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x00000000)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('lightbox_close'),
                            tooltip: 'Fermer',
                            color: Colors.white,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                          Expanded(
                            child: Text(
                              'Photo ${_index + 1}/$total',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (caption.isNotEmpty)
              _fade(
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xB3000000), Color(0x00000000)],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                        child: Text(
                          caption,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (wide && _index > 0)
              _fade(_sideArrow(left: true)),
            if (wide && _index < total - 1)
              _fade(_sideArrow(left: false)),
          ],
        ),
      ),
    );
  }

  Widget _fade(Widget child) => IgnorePointer(
        ignoring: !_chrome,
        child: AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: child,
        ),
      );

  Widget _sideArrow({required bool left}) => Align(
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconButton(
            tooltip: left ? 'Photo précédente' : 'Photo suivante',
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
            color: Colors.white,
            onPressed: () => _go(left ? -1 : 1),
            icon: Icon(left ? Icons.chevron_left : Icons.chevron_right,
                size: 32),
          ),
        ),
      );
}
