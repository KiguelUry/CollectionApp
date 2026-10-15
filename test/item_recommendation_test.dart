import 'package:collection_app/models/collection_category.dart';
import 'package:collection_app/models/collection_item.dart';
import 'package:collection_app/utils/item_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final item = CollectionItem(
    id: 'x',
    title: ' Azul ',
    category: CollectionCategory.boardgame,
    isWishlist: false,
    imageUrl: 'https://img/azul.jpg',
    minPlayers: 2,
    maxPlayers: 4,
    playingTime: 45,
    purchasePrice: 39.9,
    metadata: {
      'bgg_id': '230802',
      'year_published': 2017,
      'boardgame_plays': [
        {'date': '2026-01-01'},
      ],
      'games_played': 12,
      'loaned_to_name': 'Lou',
      'purchase_price': 39.9,
      'whereabouts_label': 'Chez Papa',
      'notes': 'privé',
    },
  );

  test('les données personnelles ne partent pas chez l\'ami', () {
    final payload = buildRecommendationPayload(
      item,
      senderUsername: 'kilian',
      message: '  Tu vas adorer  ',
    );
    final meta = payload['metadata'] as Map;
    expect(meta.keys, unorderedEquals(['bgg_id', 'year_published']));
    expect(payload['title'], 'Azul');
    expect(payload['category'], 'boardgame');
    expect(payload['message'], 'Tu vas adorer');
    expect(payload['sender_username'], 'kilian');
    expect(payload.containsKey('purchase_price'), isFalse);
  });

  test('1 clic : brouillon wishlist prêt à insérer', () {
    final payload = buildRecommendationPayload(item, senderUsername: 'kilian');
    final draft = wishlistDraftFromRecommendation(payload, userId: 'me')!;
    expect(draft.isWishlist, isTrue);
    expect(draft.title, 'Azul');
    expect(draft.category, CollectionCategory.boardgame);
    expect(draft.addedBy, 'me');
    expect(draft.imageUrl, 'https://img/azul.jpg');
    expect(draft.minPlayers, 2);
    expect(draft.playingTime, 45);
    expect(draft.metadata!['bgg_id'], '230802');
    expect(draft.metadata!['recommended_by'], 'kilian');

    final json = draft.toInsertJson(isWishlist: true, addedBy: 'me');
    expect(json['is_wishlist'], isTrue);
    expect(json['location_user_id'], isNull);
    expect(json['purchase_price'], isNull);
  });

  test('payload invalide → null', () {
    expect(wishlistDraftFromRecommendation(const {}, userId: 'me'), isNull);
  });
}
