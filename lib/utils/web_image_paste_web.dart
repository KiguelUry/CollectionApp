import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

StreamSubscription<html.Event>? _sub;

void bindWebImagePaste(void Function(Uint8List bytes) onImage) {
  unbindWebImagePaste();
  _sub = html.document.onPaste.listen((event) async {
    final items = event.clipboardData?.items;
    if (items == null) return;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.type.startsWith('image/')) {
        event.preventDefault();
        final file = item.getAsFile();
        if (file == null) return;
        final reader = html.FileReader();
        final done = reader.onLoad.first;
        reader.readAsArrayBuffer(file);
        await done;
        final result = reader.result;
        if (result is ByteBuffer) {
          onImage(result.asUint8List());
        }
        return;
      }
    }
  });
}

void unbindWebImagePaste() {
  _sub?.cancel();
  _sub = null;
}
