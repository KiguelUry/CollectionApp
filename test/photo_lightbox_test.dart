import 'package:collection_app/services/bgg_service.dart';
import 'package:collection_app/widgets/bgg_photo_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zoomAtPoint garde le point tapé fixe', () {
    const focal = Offset(120, 80);
    final m = zoomAtPoint(focal, 2.5);
    final mapped = MatrixUtils.transformPoint(m, focal);
    expect(mapped.dx, closeTo(focal.dx, 0.001));
    expect(mapped.dy, closeTo(focal.dy, 0.001));
    expect(m.getMaxScaleOnAxis(), closeTo(2.5, 0.001));
  });

  testWidgets('lightbox noire : compteur, légende, fermeture', (tester) async {
    const photos = [
      BggGalleryPhoto(url: 'https://cf.geekdo-images.com/a.jpg', caption: 'Boîte'),
      BggGalleryPhoto(url: 'https://cf.geekdo-images.com/b.jpg'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBggPhotoLightbox(context, photos, 0),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Photo 1/2'), findsOneWidget);
    expect(find.text('Boîte'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.clipBehavior, Clip.none);
    expect(viewer.maxScale, 5);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Photo 2/2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lightbox_close')));
    await tester.pumpAndSettle();
    expect(find.byType(BggPhotoLightbox), findsNothing);
  });
}
