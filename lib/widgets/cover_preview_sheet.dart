import 'package:flutter/material.dart';

import 'bgg_network_image.dart';

/// Affiche une couverture en plein écran (tap ou long-press sur une vignette).
Future<void> showCoverPreview(
  BuildContext context, {
  required String? imageUrl,
  String? title,
  bool bookCover = false,
  bool boxedCover = false,
}) async {
  if (imageUrl == null || imageUrl.trim().isEmpty) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => _CoverPreviewDialog(
      imageUrl: imageUrl.trim(),
      title: title,
      bookCover: bookCover,
      boxedCover: boxedCover,
    ),
  );
}

class _CoverPreviewDialog extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final bool bookCover;
  final bool boxedCover;

  const _CoverPreviewDialog({
    required this.imageUrl,
    this.title,
    this.bookCover = false,
    this.boxedCover = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          if (title != null && title!.isNotEmpty) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
          ],
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: size.width * 0.92,
                height: size.height * 0.72,
                child: bookCover
                    ? BggNetworkImage(
                        url: imageUrl,
                        bookCover: true,
                        largeSource: true,
                        fit: BoxFit.contain,
                      )
                    : boxedCover
                        ? BggNetworkImage(
                            url: imageUrl,
                            boxedCover: true,
                            largeSource: true,
                            fit: BoxFit.contain,
                          )
                        : AspectRatio(
                        aspectRatio: 63 / 88,
                        child: BggNetworkImage(
                          url: imageUrl,
                          boxedCover: true,
                          largeSource: true,
                          fit: BoxFit.contain,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
