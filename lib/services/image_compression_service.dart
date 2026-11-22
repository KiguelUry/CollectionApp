import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compresse et redimensionne une image avant upload Supabase Storage.
class ImageCompressionService {
  static const int maxDimension = 1200;
  static const int jpegQuality = 82;
  static const int targetMaxBytes = 200 * 1024;

  /// Retourne des bytes JPEG optimisés (~150–200 Ko max si possible).
  static Future<Uint8List> compressForUpload(Uint8List input) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;

    var working = decoded;
    if (working.width > maxDimension || working.height > maxDimension) {
      working = img.copyResize(
        working,
        width: working.width >= working.height ? maxDimension : null,
        height: working.height > working.width ? maxDimension : null,
      );
    }

    var quality = jpegQuality;
    var bytes = Uint8List.fromList(img.encodeJpg(working, quality: quality));

    while (bytes.length > targetMaxBytes && quality > 55) {
      quality -= 8;
      bytes = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }

    if (bytes.length > targetMaxBytes &&
        (working.width > 900 || working.height > 900)) {
      working = img.copyResize(
        working,
        width: (working.width * 0.75).round(),
        height: (working.height * 0.75).round(),
      );
      bytes = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }

    return bytes;
  }

  /// Couverture perso : côté max [maxSide] px, JPEG ~60 Ko.
  static Uint8List compressCover(Uint8List input, {int maxSide = 600}) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    var working = img.bakeOrientation(decoded);
    if (working.width > maxSide || working.height > maxSide) {
      working = img.copyResize(
        working,
        width: working.width >= working.height ? maxSide : null,
        height: working.height > working.width ? maxSide : null,
        interpolation: img.Interpolation.average,
      );
    }
    var quality = 80;
    var bytes = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    while (bytes.length > 90 * 1024 && quality > 50) {
      quality -= 10;
      bytes = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }
    return bytes;
  }
}
