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
}
