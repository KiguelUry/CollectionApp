import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<Uint8List> readPickedImageBytes(XFile picked) async {
  if (picked.path.isNotEmpty) {
    return File(picked.path).readAsBytes();
  }
  return picked.readAsBytes();
}
