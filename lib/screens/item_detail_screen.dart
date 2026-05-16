import 'package:flutter/material.dart';
import '../models/category_metadata.dart';
import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../widgets/bgg_network_image.dart';

class ItemDetailScreen extends StatelessWidget {
  final CollectionItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final metadataRows = CategoryMetadata.detailRows(item);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  item.imageUrl != null
                      ? BggNetworkImage(url: item.imageUrl!)
                      : Container(color: item.category.color),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(item.category.icon, size: 18),
                          label: Text(item.category.label),
                        ),
                        if (item.bookSubcategory != null)
                          Chip(label: Text(item.bookSubcategory!.label)),
                        if (item.cardSubcategory != null)
                          Chip(label: Text(item.cardSubcategory!.label)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (item.category == CollectionCategory.boardgame) ...[
                      _buildSectionTitle('Informations'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _infoTile(
                            Icons.people,
                            '${item.minPlayers ?? '?'}-${item.maxPlayers ?? '?'}',
                          ),
                          _infoTile(
                            Icons.timer,
                            item.playingTime != null
                                ? '${item.playingTime} min'
                                : '?',
                          ),
                        ],
                      ),
                      const Divider(height: 40),
                    ],
                    if (metadataRows.isNotEmpty) ...[
                      _buildSectionTitle('Détails'),
                      ...metadataRows.map(
                        (row) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            row.key,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            row.value,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 40),
                    ],
                    _buildSectionTitle('Notes'),
                    Text(
                      item.personalRules ??
                          'Aucune note pour cet objet.',
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 30),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
