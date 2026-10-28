import 'package:flutter/material.dart';

/// Sous-type pour la catégorie Livres (manga, BD, comics, roman…).
enum BookSubcategory {
  manga,
  comic, // BD franco-belge
  comics, // Comics US / anglo
  novel,
  other;

  String get dbValue => name;

  String get label => switch (this) {
        BookSubcategory.manga => 'Manga',
        BookSubcategory.comic => 'BD',
        BookSubcategory.comics => 'Comics',
        BookSubcategory.novel => 'Roman',
        BookSubcategory.other => 'Autre',
      };

  String get filterLabel => switch (this) {
        BookSubcategory.manga => '⛩️ Manga',
        BookSubcategory.comic => '💬 BD',
        BookSubcategory.comics => '🦸 Comics',
        BookSubcategory.novel => '📖 Roman',
        BookSubcategory.other => 'Autre',
      };

  /// Emoji seul (évite le texte tronqué dans les FilterChip étroits).
  String get filterEmoji => switch (this) {
        BookSubcategory.manga => '⛩️',
        BookSubcategory.comic => '💬',
        BookSubcategory.comics => '🦸',
        BookSubcategory.novel => '📖',
        BookSubcategory.other => '📚',
      };

  String get description => switch (this) {
        BookSubcategory.manga => 'Séries, tomes, scan ISBN',
        BookSubcategory.comic => 'BD franco-belge',
        BookSubcategory.comics => 'Comics & graphic novels',
        BookSubcategory.novel => 'Romans & essais',
        BookSubcategory.other => 'Tous types de livres',
      };

  String get searchHint => switch (this) {
        BookSubcategory.manga => 'One Piece, Naruto, Demon Slayer…',
        BookSubcategory.comic => 'Astérix, Tintin, Thorgal…',
        BookSubcategory.comics => 'Batman, Saga, Watchmen…',
        BookSubcategory.novel => 'Titre ou auteur…',
        BookSubcategory.other => 'Titre du livre…',
      };

  IconData get icon => switch (this) {
        BookSubcategory.manga => Icons.auto_stories_rounded,
        BookSubcategory.comic => Icons.menu_book_rounded,
        BookSubcategory.comics => Icons.flash_on_rounded,
        BookSubcategory.novel => Icons.import_contacts_rounded,
        BookSubcategory.other => Icons.book_rounded,
      };

  Color get color => switch (this) {
        BookSubcategory.manga => const Color(0xFF00A896),
        BookSubcategory.comic => const Color(0xFFE67E22),
        BookSubcategory.comics => const Color(0xFF5C6BC0),
        BookSubcategory.novel => const Color(0xFFBA4A00),
        BookSubcategory.other => Colors.blueGrey,
      };

  /// Filtres collection (sans « Autre » dans la barre principale).
  static List<BookSubcategory> get filterChips => [
        BookSubcategory.manga,
        BookSubcategory.comic,
        BookSubcategory.comics,
        BookSubcategory.novel,
      ];

  static BookSubcategory fromDbValue(String? value) {
    if (value == null) return BookSubcategory.other;
    // Ancien libellé unique « BD / Comics » → BD.
    if (value == 'bd') return BookSubcategory.comic;
    if (value == 'roman') return BookSubcategory.novel;
    return BookSubcategory.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => BookSubcategory.other,
    );
  }

  /// Valeur acceptée par l’ancienne contrainte SQL (`comic` pas `comics`).
  String get legacyDbValue => switch (this) {
        BookSubcategory.comics => BookSubcategory.comic.dbValue,
        BookSubcategory.novel => 'novel',
        _ => dbValue,
      };

  Map<String, String> openLibraryQueryParams(String query) {
    final q = query.trim();
    return switch (this) {
      BookSubcategory.manga => {
          'q': q,
          'subject': 'manga',
        },
      BookSubcategory.comic => {
          'q': q,
          'subject': 'bande dessinée',
        },
      BookSubcategory.comics => {
          'q': q,
          'subject': 'comics',
        },
      BookSubcategory.novel => {
          'q': '$q -subject:comics -subject:manga',
          'subject': 'fiction',
          'language': 'fre',
        },
      BookSubcategory.other => {'q': q, 'language': 'fre'},
    };
  }

  bool matchesOpenLibraryDoc(Map<String, dynamic> doc) {
    final subjects = (doc['subject'] as List<dynamic>?)
            ?.map((s) => s.toString().toLowerCase())
            .toList() ??
        const <String>[];

    bool has(String needle) => subjects.any((s) => s.contains(needle));

    return switch (this) {
      BookSubcategory.manga =>
        has('manga') || has('comic books, strips'),
      BookSubcategory.comic =>
        has('bande dessinée') ||
            has('bandes dessinées') ||
            has('graphic novel') ||
            (has('comic') && !has('superhero')),
      BookSubcategory.comics =>
        has('comic') || has('superhero') || has('graphic novel'),
      BookSubcategory.novel =>
        !has('manga') &&
            !has('comic') &&
            !has('graphic novel') &&
            (has('fiction') ||
                has('roman') ||
                has('literature') ||
                subjects.isEmpty),
      BookSubcategory.other => true,
    };
  }
}
