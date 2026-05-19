/// Pluriel français pour « jeu » (évite « jeus »).
String jeuxCountLabel(int count) {
  if (count == 0) return '0 jeu';
  if (count == 1) return '1 jeu';
  return '$count jeux';
}
