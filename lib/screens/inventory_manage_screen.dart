import 'package:flutter/material.dart';
import '../models/collection_item.dart';
import '../services/inventory_service.dart';
import '../utils/collection_grid_grouper.dart';
import '../utils/collection_grid_layout.dart';
import '../widgets/bgg_network_image.dart';
import '../widgets/collection_item_tile.dart';
import '../widgets/app_app_bar.dart';
import 'item_detail_screen.dart';

/// Doublons, objets à vendre/échanger, et historique vendu.
class InventoryManageScreen extends StatefulWidget {
  const InventoryManageScreen({super.key});

  @override
  State<InventoryManageScreen> createState() => _InventoryManageScreenState();
}

class _InventoryManageScreenState extends State<InventoryManageScreen> {
  final _inventory = InventoryService();
  List<GroupedCollectionItem> _duplicates = [];
  List<CollectionItem> _forSale = [];
  List<CollectionItem> _sold = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _inventory.fetchDuplicates(),
        _inventory.fetchForSale(),
        _inventory.fetchSold(),
      ]);
      _duplicates = results[0] as List<GroupedCollectionItem>;
      _forSale = results[1] as List<CollectionItem>;
      _sold = results[2] as List<CollectionItem>;
    } catch (_) {
      _duplicates = [];
      _forSale = [];
      _sold = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openItem(CollectionItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => ItemDetailScreen(item: item)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const AppAppBar(
          title: 'Doubles & ventes',
          bottom: TabBar(
            tabs: [
              Tab(text: 'Doublons'),
              Tab(text: 'À vendre'),
              Tab(text: 'Vendus'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildDuplicatesTab(),
                  _buildForSaleTab(),
                  _buildSoldTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildDuplicatesTab() {
    if (_duplicates.isEmpty) {
      return _emptyState(
        icon: Icons.copy_all,
        title: 'Aucun doublon',
        hint:
            'Les objets en double (même titre ou quantité > 1) apparaîtront ici.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _duplicates.length,
        itemBuilder: (context, index) {
          final entry = _duplicates[index];
          final item = entry.item;
          return Card(
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: item.imageUrl != null
                      ? BggNetworkImage(url: item.imageUrl!)
                      : ColoredBox(
                          color: item.category.color.withValues(alpha: 0.15),
                          child: Icon(item.category.icon, color: item.category.color),
                        ),
                ),
              ),
              title: Text(item.title),
              subtitle: Text(
                '×${entry.totalQuantity} · ${item.category.label}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'sale') {
                    await _inventory.setForSale(item.id, true);
                    _load();
                  } else if (action == 'detail') {
                    _openItem(item);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'sale',
                    child: Text('Marquer à vendre'),
                  ),
                  const PopupMenuItem(
                    value: 'detail',
                    child: Text('Voir la fiche'),
                  ),
                ],
              ),
              onTap: () => _openItem(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForSaleTab() {
    if (_forSale.isEmpty) {
      return _emptyState(
        icon: Icons.sell_outlined,
        title: 'Rien à vendre pour l\'instant',
        hint:
            'Depuis une fiche objet, active « À vendre / échanger » ou marque un doublon.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: CollectionGridLayout.gridDelegate(
          context,
          mobileColumns: 3,
          childAspectRatio: 0.85,
        ),
        itemCount: _forSale.length,
        itemBuilder: (context, index) {
          final item = _forSale[index];
          return CollectionItemTile(
            item: item,
            category: item.category,
            totalQuantity: item.quantity,
            showDuplicateBadge: item.quantity > 1,
            onTap: () => _openItem(item),
          );
        },
      ),
    );
  }

  Widget _buildSoldTab() {
    if (_sold.isEmpty) {
      return _emptyState(
        icon: Icons.history,
        title: 'Aucun objet vendu',
        hint:
            'Marque un objet comme « Vendu » pour le garder en historique (tuile grisée).',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: CollectionGridLayout.gridDelegate(
          context,
          mobileColumns: 3,
          childAspectRatio: 0.85,
        ),
        itemCount: _sold.length,
        itemBuilder: (context, index) {
          final item = _sold[index];
          return CollectionItemTile(
            item: item,
            category: item.category,
            totalQuantity: item.quantity,
            onTap: () => _openItem(item),
          );
        },
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String hint,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
