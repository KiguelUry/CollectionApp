import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// Recadrage avatar — capture WYSIWYG de la zone affichée (zoom + pan).
class AvatarCropSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const AvatarCropSheet({super.key, required this.imageBytes});

  static Future<Uint8List?> show(BuildContext context, Uint8List bytes) {
    return showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => AvatarCropSheet(imageBytes: bytes),
    );
  }

  @override
  State<AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<AvatarCropSheet> {
  static const _viewSize = 300.0;

  final _transform = TransformationController();
  final _captureKey = GlobalKey();
  bool _processing = false;
  ui.Image? _previewImage;

  @override
  void initState() {
    super.initState();
    _decodePreview();
  }

  @override
  void dispose() {
    _transform.dispose();
    _previewImage?.dispose();
    super.dispose();
  }

  Future<void> _decodePreview() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _previewImage = frame.image);
  }

  Future<Uint8List?> _captureCrop() async {
    final boundary = _captureKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final captured = await boundary.toImage(pixelRatio: 2);
    final byteData =
        await captured.toByteData(format: ui.ImageByteFormat.png);
    captured.dispose();
    if (byteData == null) return null;

    final pngBytes = byteData.buffer.asUint8List();
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;

    final resized = img.copyResize(decoded, width: 512, height: 512);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 92));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Recadrer la photo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pincez pour zoomer, glissez pour repositionner, puis validez.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: _viewSize,
            height: _viewSize,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (_previewImage != null)
                  RepaintBoundary(
                    key: _captureKey,
                    child: SizedBox(
                      width: _viewSize,
                      height: _viewSize,
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 5,
                        panEnabled: true,
                        scaleEnabled: true,
                        boundaryMargin: const EdgeInsets.all(80),
                        child: SizedBox(
                          width: _viewSize,
                          height: _viewSize,
                          child: CustomPaint(
                            painter: _ImagePainter(_previewImage!),
                            size: const Size(_viewSize, _viewSize),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                IgnorePointer(
                  child: CustomPaint(
                    size: const Size(_viewSize, _viewSize),
                    painter: _CircleMaskPainter(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _processing ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _processing
                      ? null
                      : () async {
                          setState(() => _processing = true);
                          try {
                            final bytes = await _captureCrop();
                            if (context.mounted) {
                              Navigator.pop(context, bytes);
                            }
                          } finally {
                            if (mounted) setState(() => _processing = false);
                          }
                        },
                  child: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Valider'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;

  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = size.width / iw < size.height / ih
        ? size.width / iw
        : size.height / ih;
    final w = iw * scale;
    final h = ih * scale;
    final rect = Rect.fromLTWH(
      (size.width - w) / 2,
      (size.height - h) / 2,
      w,
      h,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) => old.image != image;
}

class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
