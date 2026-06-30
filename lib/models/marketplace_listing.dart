import '../models/collection_item.dart';
import '../utils/marketplace_status.dart';

/// Annonce visible dans l'Hôtel des Ventes / Échanges.
class MarketplaceListing {
  final CollectionItem item;
  final String ownerId;
  final String ownerUsername;
  final MarketplaceDisposition disposition;

  const MarketplaceListing({
    required this.item,
    required this.ownerId,
    required this.ownerUsername,
    required this.disposition,
  });
}

class MarketplaceInquiry {
  final String id;
  final String listingItemId;
  final String senderId;
  final String ownerId;
  final String message;
  final String? proposedItemId;
  final DateTime createdAt;

  const MarketplaceInquiry({
    required this.id,
    required this.listingItemId,
    required this.senderId,
    required this.ownerId,
    required this.message,
    this.proposedItemId,
    required this.createdAt,
  });

  factory MarketplaceInquiry.fromJson(Map<String, dynamic> json) {
    return MarketplaceInquiry(
      id: json['id'] as String,
      listingItemId: json['listing_item_id'] as String,
      senderId: json['sender_id'] as String,
      ownerId: json['owner_id'] as String,
      message: json['message'] as String,
      proposedItemId: json['proposed_item_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
