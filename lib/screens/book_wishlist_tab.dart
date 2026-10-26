import 'package:flutter/material.dart';

import 'book/book_collection_screen.dart';

/// Wishlist livres — même DA que Collection (grille / liste séries).
class BookWishlistTab extends StatelessWidget {
  const BookWishlistTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const BookCollectionScreen(
      embedded: true,
      wishlistOnly: true,
    );
  }
}
