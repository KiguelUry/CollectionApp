import 'bgg_text.dart';

/// Décode les entités HTML pour l'affichage (titres, descriptions…).
///
/// Couvre `&amp;`, `&quot;`, `&apos;`, `&#039;`, entités numériques, etc.
String cleanDisplayText(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  return decodeHtmlEntities(raw).trim();
}
