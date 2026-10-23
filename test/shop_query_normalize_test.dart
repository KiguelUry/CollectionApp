import 'package:collection_app/utils/shop_query_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeShopQuery keeps accents as ascii letters, not spaces', () {
    expect(normalizeShopQuery('Le Château Blanc'), 'Le Chateau Blanc');
    expect(normalizeShopQuery('Pokémon'), 'Pokemon');
    expect(normalizeShopQuery('Cœur de Pirate'), 'Coeur de Pirate');
  });

  test('encodeShopQuery is URI-safe', () {
    final q = encodeShopQuery('Le Château Blanc');
    expect(q.contains('Chateau'), isTrue);
    expect(q.contains(' '), isFalse);
  });
}
