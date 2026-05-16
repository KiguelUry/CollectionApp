import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../utils/collection_grid_grouper.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final CollectionGroup group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Supabase.instance.client
        .from('collection_items')
        .stream(primaryKey: ['id'])
        .eq('group_id', widget.group.id);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: CollectionCategory.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.group.name),
          bottom: TabBar(
            isScrollable: true,
            tabs: CollectionCategory.values
                .map((c) => Tab(text: c.label))
                .toList(),
          ),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Erreur : ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final all = snapshot.data!
                .map((j) => CollectionItem.fromJson(j))
                .where((i) => !i.isWishlist)
                .toList();

            return TabBarView(
              children: CollectionCategory.values.map((category) {
                final items =
                    all.where((i) => i.category == category).toList();
                final grouped = CollectionGridGrouper.group(items);
                return _buildGrid(grouped, category);
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGrid(
    List<GroupedCollectionItem> grouped,
    CollectionCategory category,
  ) {
    if (grouped.isEmpty) {
      return const Center(child: Text('Aucun objet partagé ici.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped[index];
        final item = entry.item;

        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => ItemDetailScreen(item: item),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.imageUrl != null
                          ? BggNetworkImage(url: item.imageUrl!)
                          : Container(
                              color: Colors.grey.shade200,
                              child: Icon(category.icon, color: Colors.grey),
                            ),
                    ),
                    if (entry.hasDuplicates)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '×${entry.totalQuantity}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
