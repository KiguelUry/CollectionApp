import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bgg_service.dart';
import '../utils/cover_image_url.dart';
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

Future<void> showBggPhotoLightbox(
  BuildContext context,
  List<BggGalleryPhoto> photos,
  int initialIndex,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (ctx) => _BggLightbox(photos: photos, initialIndex: initialIndex),
  );
}

class _BggLightbox extends StatefulWidget {
  final List<BggGalleryPhoto> photos;
  final int initialIndex;

  const _BggLightbox({required this.photos, required this.initialIndex});

  @override
  State<_BggLightbox> createState() => _BggLightboxState();
}

class _BggLightboxState extends State<_BggLightbox> {
  late final PageController _page;
  late int _index;

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
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1000,
            maxHeight: size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Fermer',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Flexible(
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Photo précédente',
                      color: Colors.white,
                      onPressed: _index > 0 ? () => _go(-1) : null,
                      icon: const Icon(Icons.chevron_left, size: 36),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: size.height * 0.62,
                          child: PageView.builder(
                            controller: _page,
                            itemCount: widget.photos.length,
                            onPageChanged: (value) =>
                                setState(() => _index = value),
                            itemBuilder: (context, i) {
                              final item = widget.photos[i];
                              return CollectionCoverImage(
                                url: bggMaterialPhotoUrl(
                                  item.url,
                                  width: 1400,
                                  quality: 90,
                                ),
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Photo suivante',
                      color: Colors.white,
                      onPressed: _index < widget.photos.length - 1
                          ? () => _go(1)
                          : null,
                      icon: const Icon(Icons.chevron_right, size: 36),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Photo ${_index + 1} / ${widget.photos.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (caption.isNotEmpty)
                      Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
