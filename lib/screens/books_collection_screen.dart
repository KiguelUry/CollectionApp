import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/book_accent.dart';
import '../coordinators/book_item_add_coordinator.dart';
import '../models/book_subcategory.dart';
import '../widgets/category_hub_header.dart';
import '../widgets/category_type_hub.dart';
import 'book/book_collection_screen.dart';
import 'book/user_lists_hub_screen.dart';
import 'book_subcategory_series_screen.dart';
import 'book_wishlist_tab.dart';

/// Hub découverte Livres (aligné sur jeux de société).
class BooksCollectionScreen extends StatefulWidget {
  const BooksCollectionScreen({super.key});

  @override
  State<BooksCollectionScreen> createState() => _BooksCollectionScreenState();
}

class _BooksCollectionScreenState extends State<BooksCollectionScreen> {
  static const _accent = BookAccent.primary;
  static const _tipKey = 'ux_tip_books_hub_v2';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _maybeShowTip();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            'Astuce : recherche « Naruto 1 » ou scanne l\'ISBN d\'un tome.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void _openSearch({BookSubcategory? subcategory}) {
    final q = _searchController.text.trim();
    BookItemAddCoordinator(context).openSearch(
      subcategory: subcategory,
      initialQuery: q.length >= 2 ? q : null,
    );
  }

  void _openCollection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => const BookCollectionScreen(),
      ),
    );
  }

  void _openWishlist() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Wishlist Livres'),
            backgroundColor: BookAccent.primary,
            foregroundColor: Colors.white,
          ),
          body: const BookWishlistTab(),
        ),
      ),
    );
  }

  void _openLists() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => const UserListsHubScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CategoryHubHeader(
            title: 'Livres',
            accentColor: _accent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _openSearch(),
              decoration: InputDecoration(
                hintText: 'Rechercher un livre (ex. « Dune », « One Piece 3 »)',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _openSearch(),
                ),
              ),
            ),
          ),
          Expanded(
            child: CategoryTypeHub(
              accentColor: _accent,
              title: 'Livres',
              showTitleInHero: false,
              heroWatermark: Icons.menu_book_rounded,
              subtitle:
                  'Manga, BD, romans — couvertures épurées, listes perso.',
              featuredItem: CategoryTypeHubItem(
                label: 'Ma collection',
                description:
                    'Séries et tomes — possédé, lu, ajout en un tap',
                icon: Icons.view_module_rounded,
                color: _accent,
                onTap: _openCollection,
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
                CategoryTypeHubItem(
                  label: 'Mes listes',
                  description: 'Listes thématiques · style Letterboxd',
                  icon: Icons.playlist_play_rounded,
                  color: const Color(0xFF1B7F79),
                  onTap: _openLists,
                ),
                CategoryTypeHubItem(
                  label: 'Recherche catalogue',
                  description: 'Google Books + iTunes · couvertures HD',
                  icon: Icons.travel_explore,
                  color: BookAccent.light,
                  onTap: () => _openSearch(),
                ),
                CategoryTypeHubItem(
                  label: 'Scanner ISBN',
                  description: 'Ajout rapide par code-barres',
                  icon: Icons.qr_code_scanner,
                  color: const Color(0xFF256B5C),
                  onTap: () => BookItemAddCoordinator(context).scanIsbn(),
                ),
                CategoryTypeHubItem(
                  label: 'Wishlist',
                  description: 'Livres que tu veux acquérir',
                  icon: Icons.favorite_outline,
                  color: Colors.pink.shade300,
                  onTap: _openWishlist,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
