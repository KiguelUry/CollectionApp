import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<Uint8List> readPickedImageBytes(XFile picked) => picked.readAsBytes();
