import 'package:flutter/material.dart';

import '../models/collection_category.dart';
import '../models/user_collection_type.dart';
import '../services/category_hub_preferences.dart';
import '../services/user_collection_type_service.dart';
import '../utils/category_hub_order.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/create_custom_collection_dialog.dart';

class CategoryManageScreen extends StatefulWidget {
  const CategoryManageScreen({super.key});

  @override
  State<CategoryManageScreen> createState() => _CategoryManageScreenState();
}

class _CategoryManageScreenState extends State<CategoryManageScreen> {
  final _prefs = CategoryHubPreferences.instance;
  final _customService = UserCollectionTypeService();
  List<HubTileEntry> _tiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _prefs.load();
    final customTypes = await _customService.fetchMine();
    final tiles = await CategoryHubOrder.loadOrderedTiles(customTypes);
    if (mounted) {
      setState(() {
        _tiles = tiles;
        _loading = false;
      });
    }
  }

  Future<void> _toggleCategory(CollectionCategory cat, bool visible) async {
    await _prefs.setVisible(cat, visible);
    if (mounted) setState(() {});
  }

  Future<void> _addCustom() async {
    final created = await showCreateCustomCollectionDialog(context);
    if (created != null) await _load();
  }

  Future<void> _deleteCustom(UserCollectionType type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la collection ?'),
        content: Text(
          '« ${type.name} » et tous ses objets seront supprimés définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _customService.deleteWithCleanup(type.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('« ${type.name} » supprimée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  void _onReorderItem(int oldIndex, int newIndex) {
    setState(() {
      final item = _tiles.removeAt(oldIndex);
      _tiles.insert(newIndex, item);
    });
    CategoryHubOrder.saveTileOrder(_tiles);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: 'Gestion des collections',
        actions: [
          IconButton(
            onPressed: _addCustom,
            tooltip: 'Nouvelle collection',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Glisse pour réordonner le menu principal. '
                    'Les catégories masquées restent ici mais disparaissent du hub.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: _tiles.length,
                    onReorderItem: _onReorderItem,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final entry = _tiles[index];
                      final key = ValueKey(entry.storageKey);
                      if (entry.category != null) {
                        final cat = entry.category!;
                        return _ManageTile(
                          key: key,
                          index: index,
                          leading: Icon(cat.icon, color: cat.color),
                          title: cat.label,
                          subtitle: cat.description,
                          trailing: Switch(
                            value: _prefs.isVisible(cat),
                            onChanged: (v) => _toggleCategory(cat, v),
                          ),
                        );
                      }
                      final type = entry.customType!;
                      return _ManageTile(
                        key: key,
                        index: index,
                        leading: Icon(type.icon, color: type.color),
                        title: type.name,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteCustom(type),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  final int index;
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _ManageTile({
    super.key,
    required this.index,
    required this.leading,
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            trailing,
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.drag_handle,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
