/// Libellé sous la barre de recherche des collections.
String formatCollectionCountLabel({
  required int total,
  required int inGroup,
}) {
  if (total <= 0) return '0 objet';
  final objectWord = total > 1 ? 'objets' : 'objet';
  if (inGroup > 0) {
    final groupWord = inGroup > 1 ? 'groupes' : 'groupe';
    return '$total $objectWord dont $inGroup en $groupWord';
  }
  return '$total $objectWord';
}
