import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../widgets/app_app_bar.dart';
import '../coordinators/book_item_add_coordinator.dart';
import '../widgets/category_type_hub.dart';
import '../widgets/ui/hub_search_bar.dart';
import 'book_subcategory_series_screen.dart';
import 'book_wishlist_tab.dart';
import 'home_screen.dart';

/// Point d'entrée Livres : choix du type puis séries.
class BooksCollectionScreen extends StatefulWidget {
  const BooksCollectionScreen({super.key});

  @override
  State<BooksCollectionScreen> createState() => _BooksCollectionScreenState();
}

class _BooksCollectionScreenState extends State<BooksCollectionScreen> {
  static const _accent = Color(0xFF5E35B1);
  static const _tipKey = 'ux_tip_books_hub';

  @override
  void initState() {
    super.initState();
    _maybeShowTip();
  }

  Future<void> _maybeShowTip() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_tipKey) == true) return;
    await prefs.setBool(_tipKey, true);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text(
            'Astuce : recherche « One Piece » ou scanne l\'ISBN d\'un tome.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const AppAppBar(
          title: 'Livres',
          bottom: TabBar(
            tabs: [
              Tab(text: 'Explorer'),
              Tab(text: 'Wishlist'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            CategoryTypeHub(
              accentColor: _accent,
              title: 'Ta bibliothèque',
              subtitle:
                  'Manga, BD, romans — organise par séries et tomes.',
              header: HubSearchBar(
                accent: _accent,
                hint: 'Rechercher un livre',
                subtitle: 'One Piece, Astérix, etc.',
                icon: Icons.menu_book_rounded,
                onTap: () => BookItemAddCoordinator(context).openSearch(),
              ),
              items: [
                for (final sub in BookSubcategory.values)
                  CategoryTypeHubItem(
                    label: sub.label,
                    description: sub.description,
                    icon: sub.icon,
                    color: sub.color,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) =>
                              BookSubcategorySeriesScreen(subcategory: sub),
                        ),
                      );
                    },
                  ),
              ],
              onClassicList: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const HomeScreen(
                      category: CollectionCategory.book,
                    ),
                  ),
                );
              },
            ),
            const BookWishlistTab(),
          ],
        ),
      ),
    );
  }
}
