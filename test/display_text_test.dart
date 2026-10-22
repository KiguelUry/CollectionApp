import 'package:collection_app/utils/display_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('décode apostrophes et ampersands HTML', () {
    expect(
      cleanDisplayText("Sub Terra II: Inferno&#039;s Edge"),
      "Sub Terra II: Inferno's Edge",
    );
    expect(cleanDisplayText("Wonderland&#039;s War"), "Wonderland's War");
    expect(cleanDisplayText('Sea Salt &amp; Paper'), 'Sea Salt & Paper');
    expect(cleanDisplayText('A &quot;quote&quot;'), 'A "quote"');
    expect(cleanDisplayText('Ra &apos;99'), "Ra '99");
  });
}
