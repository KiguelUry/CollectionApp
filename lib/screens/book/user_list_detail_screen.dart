import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/collection_item.dart';
import '../../models/user_list.dart';
import '../../services/user_list_service.dart';
import '../../utils/collection_grid_layout.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/collection_item_tile.dart';
import '../item_detail_screen.dart';

class UserListDetailScreen extends StatefulWidget {
  final String listId;

  const UserListDetailScreen({super.key, required this.listId});

  @override
  State<UserListDetailScreen> createState() => _UserListDetailScreenState();
}

class _UserListDetailScreenState extends State<UserListDetailScreen> {
  final _service = UserListService();
  bool _loading = true;
  UserListWithItems? _bundle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bundle = await _service.fetchWithItems(widget.listId);
      if (mounted) {
        setState(() {
          _bundle = bundle;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _addItems() async {
    final candidates = await _service.fetchAddableItems(widget.listId);

    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun élément disponible à ajouter')),
      );
      return;
    }

    final selected = await showModalBottomSheet<CollectionItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ajouter à la liste',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: candidates.length,
                itemBuilder: (context, i) {
                  final item = candidates[i];
                  return ListTile(
                    leading: item.imageUrl != null && item.imageUrl!.isNotEmpty
                        ? Image.network(
                            item.imageUrl!,
                            width: 36,
                            height: 52,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.menu_book_outlined),
                    title: Text(item.title),
                    subtitle: Text(item.listSubtitle ?? ''),
                    onTap: () => Navigator.pop(ctx, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    await _service.addItem(widget.listId, selected.id);
    _load();
  }

  Future<void> _removeItem(CollectionItem item) async {
    await _service.removeItem(widget.listId, item.id);
    _load();
  }

  Future<void> _deleteList() async {
    final list = _bundle?.list;
    if (list == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la liste ?'),
        content: Text('« ${list.name} » sera supprimée (les livres restent).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.delete(list.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    return Scaffold(
      appBar: AppAppBar(
        title: bundle?.list.name ?? 'Liste',
        backgroundColor: BookAccent.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer la liste',
            onPressed: _deleteList,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItems,
        backgroundColor: BookAccent.primary,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : bundle == null
              ? const Center(child: Text('Liste introuvable'))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: BookAccent.primary,
                  child: CustomScrollView(
                    slivers: [
                      if (bundle.list.description != null &&
                          bundle.list.description!.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text(
                              bundle.list.description!,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      if (bundle.items.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'Liste vide.\nAjoute des livres avec le bouton +',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 88),
                          sliver: SliverGrid(
                            gridDelegate:
                                CollectionGridLayout.gridDelegate(
                              context,
                              mobileColumns: 3,
                              childAspectRatio: 0.68,
                              spacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = bundle.items[index];
                                return CollectionItemTile(
                                  item: item,
                                  category: item.category,
                                  coverFirst: true,
                                  showGroupBadge: false,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) =>
                                          ItemDetailScreen(item: item),
                                    ),
                                  ),
                                  onDelete: () => _removeItem(item),
                                );
                              },
                              childCount: bundle.items.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
