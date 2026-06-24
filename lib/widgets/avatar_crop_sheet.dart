import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Prévisualisation avec recadrage circulaire avant upload avatar.
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
  final _transform = TransformationController();
  bool _processing = false;

  Future<Uint8List?> _crop() async {
    setState(() => _processing = true);
    try {
      final decoded = img.decodeImage(widget.imageBytes);
      if (decoded == null) return null;

      final matrix = _transform.value;
      final scale = matrix.getMaxScaleOnAxis();
      final tx = matrix.getTranslation().x;
      final ty = matrix.getTranslation().y;

      const viewSize = 280.0;
      final cropSize = (viewSize / scale).round().clamp(1, decoded.width);
      final centerX = decoded.width / 2 - tx / scale;
      final centerY = decoded.height / 2 - ty / scale;
      var left = (centerX - cropSize / 2).round();
      var top = (centerY - cropSize / 2).round();
      left = left.clamp(0, decoded.width - cropSize);
      top = top.clamp(0, decoded.height - cropSize);

      final cropped = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: cropSize,
        height: cropSize,
      );
      final resized = img.copyResize(cropped, width: 512, height: 512);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
            'Pincez et déplacez pour centrer votre visage.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 280,
            height: 280,
            child: ClipOval(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 0.5,
                maxScale: 4,
                child: Image.memory(
                  widget.imageBytes,
                  fit: BoxFit.cover,
                  width: 280,
                  height: 280,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _processing
                      ? null
                      : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _processing
                      ? null
                      : () async {
                          final bytes = await _crop();
                          if (context.mounted) Navigator.pop(context, bytes);
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
