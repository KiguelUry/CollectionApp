import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/collection_item.dart';
import '../../models/marketplace_listing.dart';
import '../../services/marketplace_service.dart';
import '../../utils/collection_item_scope.dart';
import '../../utils/supabase_embeds.dart';
import '../bgg_network_image.dart';

/// Composer un message d'intérêt (+ proposition de troc optionnelle).
Future<void> showMarketplaceInquirySheet(
  BuildContext context, {
  required MarketplaceListing listing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _MarketplaceInquirySheet(listing: listing),
  );
}

class _MarketplaceInquirySheet extends StatefulWidget {
  final MarketplaceListing listing;

  const _MarketplaceInquirySheet({required this.listing});

  @override
  State<_MarketplaceInquirySheet> createState() =>
      _MarketplaceInquirySheetState();
}

class _MarketplaceInquirySheetState extends State<_MarketplaceInquirySheet> {
  final _service = MarketplaceService();
  final _messageController = TextEditingController();
  List<CollectionItem> _myItems = [];
  CollectionItem? _proposedItem;
  bool _loadingItems = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMyItems();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMyItems() async {
    final userId = CollectionItemScope.currentUserId;
    if (userId == null) {
      setState(() => _loadingItems = false);
      return;
    }
    try {
      final rows = await CollectionItemScope.personal(
        Supabase.instance.client
            .from('collection_items')
            .select(SupabaseEmbeds.collectionItemList),
        userId: userId,
      );
      final items = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .where((i) => !i.isWishlist && !i.isSold)
          .toList()
        ..sort((a, b) => a.title.compareTo(b.title));
      if (mounted) {
        setState(() {
          _myItems = items;
          _loadingItems = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendInquiry(
        listing: widget.listing,
        message: text,
        proposedItemId: _proposedItem?.id,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.listing.ownerUsername} a reçu ton message.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible d\'envoyer (table marketplace_inquiries ?) : $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final item = listing.item;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Contacter ${listing.ownerUsername}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: item.imageUrl != null
                        ? BggNetworkImage(
                            url: item.imageUrl!,
                            fit: BoxFit.cover,
                            boxedCover: true,
                          )
                        : ColoredBox(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.inventory_2_outlined),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Ton message',
                hintText: 'Bonjour, cet objet m\'intéresse…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Proposer un troc (optionnel)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (_loadingItems)
              const LinearProgressIndicator(minHeight: 2)
            else if (_myItems.isEmpty)
              Text(
                'Aucun objet dans ta collection à proposer.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              DropdownButtonFormField<String?>(
                value: _proposedItem?.id,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                hint: const Text('Choisir un de tes objets'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Aucune proposition'),
                  ),
                  ..._myItems.map(
                    (i) => DropdownMenuItem<String?>(
                      value: i.id,
                      child: Text(i.title, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (id) {
                  setState(() {
                    _proposedItem = id == null
                        ? null
                        : _myItems.firstWhere((i) => i.id == id);
                  });
                },
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }
}
