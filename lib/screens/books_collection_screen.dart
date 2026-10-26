import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../coordinators/book_item_add_coordinator.dart';
import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../widgets/app_app_bar.dart';
import 'book/book_collection_screen.dart';
import 'book/user_lists_hub_screen.dart';
import 'book_wishlist_tab.dart';
import 'collection_change_history_screen.dart';

/// Accueil Livres — entrée directe Collection / Wishlist (comme les jeux).
class BooksCollectionScreen extends StatefulWidget {
  const BooksCollectionScreen({super.key});

  @override
  State<BooksCollectionScreen> createState() => _BooksCollectionScreenState();
}

class _BooksCollectionScreenState extends State<BooksCollectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openSearch({BookSubcategory? subcategory}) async {
    await BookItemAddCoordinator(context).openSearch(subcategory: subcategory);
    // Rafraîchissement Mes livres via CollectionRefresh (écouteur) + cache.
  }

  void _scanIsbn() {
    BookItemAddCoordinator(context).scanIsbn();
  }

  void _openLists() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserListsHubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = BookAccent.primary;
    return Scaffold(
      appBar: AppAppBar(
        title: 'Mes livres',
        backgroundColor: accent,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Collection'),
            Tab(text: 'Wishlist'),
          ],
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                _ToolPill(
                  icon: Icons.auto_awesome,
                  label: 'Découvrir',
                  onTap: () => _openSearch(),
                ),
                _ToolPill(
                  icon: Icons.menu_book_outlined,
                  label: 'Pile à lire',
                  onTap: () => _tabs.animateTo(0),
                ),
                _ToolPill(
                  icon: Icons.qr_code_scanner,
                  label: 'Scanner ISBN',
                  onTap: _scanIsbn,
                ),
                _ToolPill(
                  icon: Icons.list_alt,
                  label: 'Mes listes',
                  onTap: _openLists,
                ),
                _ToolPill(
                  icon: Icons.restore_rounded,
                  label: 'Modifs',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CollectionChangeHistoryScreen(
                        category: CollectionCategory.book,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                BookCollectionScreen(embedded: true),
                BookWishlistTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSearch(),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
}

class _ToolPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }
}
