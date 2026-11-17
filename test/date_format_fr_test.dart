import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  test('DateFormat fr_FR fonctionne après initializeDateFormatting', () async {
    await initializeDateFormatting('fr_FR');
    final formatted = DateFormat('d MMM yyyy', 'fr_FR').format(
      DateTime(2026, 11, 16),
    );
    expect(formatted, isNotEmpty);
    expect(formatted.toLowerCase(), contains('2026'));
  });
}
