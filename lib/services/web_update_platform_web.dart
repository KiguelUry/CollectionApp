import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

StreamSubscription<html.Event>? _visSub;

void bindVisibilityChange(void Function() onVisible) {
  unbindVisibilityChange();
  _visSub = html.document.onVisibilityChange.listen((_) {
    if (html.document.hidden == false) onVisible();
  });
}

void unbindVisibilityChange() {
  _visSub?.cancel();
  _visSub = null;
}

Future<void> clearWebCaches() async {
  try {
    final caches = js_util.getProperty(html.window, 'caches');
    if (caches != null) {
      final keys = await js_util.promiseToFuture<List<dynamic>>(
        js_util.callMethod(caches, 'keys', const []),
      );
      for (final key in keys) {
        await js_util.promiseToFuture(
          js_util.callMethod(caches, 'delete', [key]),
        );
      }
    }
  } catch (_) {}
}

void reloadPage() {
  html.window.location.reload();
}
