/// Sous-type pour la catégorie Livres (manga, BD, roman, etc.)
enum BookSubcategory {
  manga,
  comic,
  novel,
  other;

  String get dbValue => name;

  String get label => switch (this) {
        BookSubcategory.manga => 'Manga',
        BookSubcategory.comic => 'BD / Comics',
        BookSubcategory.novel => 'Roman',
        BookSubcategory.other => 'Autre',
      };

  static BookSubcategory fromDbValue(String? value) {
    if (value == null) return BookSubcategory.other;
    return BookSubcategory.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => BookSubcategory.other,
    );
  }

  /// Paramètres Open Library pour ne retourner que ce type de livre.
  Map<String, String> openLibraryQueryParams(String query) {
    final q = query.trim();
    return switch (this) {
      BookSubcategory.manga => {
          'q': q,
          'subject': 'manga',
        },
      BookSubcategory.comic => {
          'q': q,
          'subject': 'comics',
        },
      BookSubcategory.novel => {
          'q': '$q -subject:comics -subject:manga',
          'subject': 'fiction',
        },
      BookSubcategory.other => {'q': q},
    };
  }

  /// Filtre côté client si l'API renvoie encore des hors-sujet.
  bool matchesOpenLibraryDoc(Map<String, dynamic> doc) {
    final subjects = (doc['subject'] as List<dynamic>?)
            ?.map((s) => s.toString().toLowerCase())
            .toList() ??
        const <String>[];

    bool has(String needle) =>
        subjects.any((s) => s.contains(needle));

    return switch (this) {
      BookSubcategory.manga =>
        has('manga') || has('comic books, strips'),
      BookSubcategory.comic =>
        has('comic') ||
        has('graphic novel') ||
        has('bande dessinée') ||
        has('bandes dessinées'),
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
