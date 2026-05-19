import 'package:flutter/material.dart';

import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../widgets/app_app_bar.dart';
import 'book_subcategory_series_screen.dart';
import 'book_wishlist_tab.dart';
import 'home_screen.dart';

/// Point d'entrée Livres : choix du type puis séries.
class BooksCollectionScreen extends StatelessWidget {
  const BooksCollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const AppAppBar(
          title: 'Livres',
          bottom: TabBar(
            tabs: [
              Tab(text: 'Par série'),
              Tab(text: 'Wishlist'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TypePicker(onOpen: (sub) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) =>
                      BookSubcategorySeriesScreen(subcategory: sub),
                ),
              );
            }),
            const BookWishlistTab(),
          ],
        ),
      ),
    );
  }
}

class _TypePicker extends StatelessWidget {
  final void Function(BookSubcategory sub) onOpen;

  const _TypePicker({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Quel type de livres ?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        for (final sub in BookSubcategory.values)
          Card(
            child: ListTile(
              leading: Icon(_icon(sub)),
              title: Text(sub.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(sub),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) =>
                    const HomeScreen(category: CollectionCategory.book),
              ),
            );
          },
          icon: const Icon(Icons.view_list_outlined),
          label: const Text('Vue liste classique (tous les livres)'),
        ),
      ],
    );
  }

  IconData _icon(BookSubcategory s) => switch (s) {
        BookSubcategory.manga => Icons.auto_stories_outlined,
        BookSubcategory.comic => Icons.menu_book_outlined,
        BookSubcategory.novel => Icons.import_contacts_outlined,
        BookSubcategory.other => Icons.book_outlined,
      };
}
