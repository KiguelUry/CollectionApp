import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../coordinators/book_item_add_coordinator.dart';
import '../models/book_subcategory.dart';
import '../models/collection_category.dart';
import '../widgets/category_collection_header.dart';
import '../widgets/category_collection_shell.dart';
import 'book/book_collection_screen.dart';
import 'book/book_discover_screen.dart';
import 'book/book_reading_pile_screen.dart';
import 'book/user_lists_hub_screen.dart';
import 'book_wishlist_tab.dart';
import 'collection_change_history_screen.dart';

/// Accueil Livres — même DA que « Mes jeux de société » (header coloré + actions).
class BooksCollectionScreen extends StatefulWidget {
  const BooksCollectionScreen({super.key});

  @override
  State<BooksCollectionScreen> createState() => _BooksCollectionScreenState();
}

class _BooksCollectionScreenState extends State<BooksCollectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _compactActions = false;

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

  List<CategoryQuickAction> get _quickActions => [
        CategoryQuickAction(
          label: 'Découvrir',
          icon: Icons.auto_awesome,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BookDiscoverScreen()),
          ),
        ),
        CategoryQuickAction(
          label: 'Pile à lire',
          icon: Icons.menu_book_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BookReadingPileScreen()),
          ),
        ),
        CategoryQuickAction(
          label: 'Scanner ISBN',
          icon: Icons.qr_code_scanner_rounded,
          onTap: _scanIsbn,
        ),
        CategoryQuickAction(
          label: 'Mes listes',
          icon: Icons.list_alt_rounded,
          onTap: _openLists,
        ),
        CategoryQuickAction(
          label: 'Modifs',
          icon: Icons.restore_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CollectionChangeHistoryScreen(
                category: CollectionCategory.book,
              ),
            ),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    const accent = BookAccent.primary;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSearch(),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: NestedScrollView(
        floatHeaderSlivers: false,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          final compact = innerBoxIsScrolled;
          if (compact != _compactActions) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _compactActions = compact);
            });
          }
          // SafeArea du header gère le notch (native) ; sur web = 0 (pas de double bande).
          final top = kIsWeb ? 0.0 : MediaQuery.paddingOf(context).top;
          final toolbar = compact ? 36.0 : 44.0;
          final headerH = top + 40 + 36 + toolbar + 6;
          return [
            SliverAppBar(
              floating: false,
              pinned: true,
              primary: false,
              automaticallyImplyLeading: false,
              backgroundColor: accent,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 0,
              forceElevated: innerBoxIsScrolled,
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(headerH),
                child: CategoryCollectionHeader(
                  category: CollectionCategory.book,
                  title: 'Mes livres',
                  tabController: _tabs,
                  accentOverride: accent,
                  quickActions: _quickActions,
                  compactActions: compact,
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabs,
          children: const [
            BookCollectionScreen(embedded: true),
            BookWishlistTab(),
          ],
        ),
      ),
    );
  }
}
