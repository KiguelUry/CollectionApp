import 'package:flutter/material.dart';

import '../../models/collection_category.dart';
import '../../models/marketplace_listing.dart';
import '../../services/marketplace_service.dart';
import '../../utils/marketplace_status.dart';
import '../../widgets/bgg_network_image.dart';
import '../../widgets/marketplace/marketplace_inquiry_sheet.dart';

/// Espace dédié vente / échange (hors vue collection).
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _service = MarketplaceService();
  List<MarketplaceListing> _listings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchGroupListings();
      if (mounted) {
        setState(() {
          _listings = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hôtel des Ventes / Échanges'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _listings.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Icon(Icons.storefront_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text(
                            'Aucune annonce pour l\'instant.\n'
                            'Les membres de tes groupes peuvent marquer\n'
                            'leurs objets « À vendre » ou « Recherche d\'échange ».',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _listings.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = _listings[index];
                          return _ListingCard(
                            listing: entry,
                            onChat: () => showMarketplaceInquirySheet(
                              context,
                              listing: entry,
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final MarketplaceListing listing;
  final VoidCallback onChat;

  const _ListingCard({
    required this.listing,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final item = listing.item;
    final disposition = listing.disposition;
    final badgeColor = switch (disposition) {
      MarketplaceDisposition.forSale => Colors.orange.shade800,
      MarketplaceDisposition.wantsTrade => Colors.teal.shade700,
      _ => Colors.grey,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onChat,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: item.imageUrl != null
                      ? BggNetworkImage(
                          url: item.imageUrl!,
                          fit: BoxFit.cover,
                          boxedCover:
                              item.category == CollectionCategory.boardgame,
                        )
                      : ColoredBox(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.inventory_2_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      listing.ownerUsername,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        marketplaceDispositionLabel(disposition),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Discuter',
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
