import 'package:xml/xml.dart';

/// Jeu de la collection BGG d'un utilisateur (`xmlapi2/collection`).
class BggCollectionEntry {
  final String bggId;
  final String title;
  final int? year;
  final String? imageUrl;
  final String? thumbnailUrl;
  final int? minPlayers;
  final int? maxPlayers;
  final int? playingTime;
  final bool isExpansion;

  const BggCollectionEntry({
    required this.bggId,
    required this.title,
    this.year,
    this.imageUrl,
    this.thumbnailUrl,
    this.minPlayers,
    this.maxPlayers,
    this.playingTime,
    this.isExpansion = false,
  });

  factory BggCollectionEntry.fromJson(Map<dynamic, dynamic> json) {
    int? asInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
    String? url(Object? v) => _normalizeUrl(v?.toString());
    return BggCollectionEntry(
      bggId: json['bgg_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      year: asInt(json['year']),
      imageUrl: url(json['image_url']),
      thumbnailUrl: url(json['thumbnail_url']),
      minPlayers: asInt(json['min_players']),
      maxPlayers: asInt(json['max_players']),
      playingTime: asInt(json['playing_time']),
      isExpansion: json['is_expansion'] == true,
    );
  }
}

String? _normalizeUrl(String? raw) {
  final t = raw?.trim();
  if (t == null || t.isEmpty) return null;
  return t.startsWith('//') ? 'https:$t' : t;
}

int? _positive(int? v) => v != null && v > 0 ? v : null;

/// Message d'erreur BGG (`<errors><error><message>`), sinon `null`.
String? bggCollectionXmlError(String xml) {
  try {
    final doc = XmlDocument.parse(xml);
    final msg = doc.findAllElements('error').firstOrNull;
    if (msg == null) return null;
    final text =
        msg.findElements('message').firstOrNull?.innerText.trim() ??
        msg.innerText.trim();
    return text.isEmpty ? 'Erreur BGG' : text;
  } catch (_) {
    return null;
  }
}

/// BGG met la collection en file d'attente (HTTP 202 ou message « try again »).
bool isBggCollectionPending(int statusCode, String body) =>
    statusCode == 202 || body.contains('Please try again later');

List<BggCollectionEntry> parseBggCollectionXml(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (_) {
    return [];
  }
  final out = <BggCollectionEntry>[];
  final seen = <String>{};
  for (final item in doc.findAllElements('item')) {
    final id = item.getAttribute('objectid') ?? '';
    if (id.isEmpty || !seen.add(id)) continue;
    final stats = item.findElements('stats').firstOrNull;
    int? statAttr(String name) => int.tryParse(stats?.getAttribute(name) ?? '');
    final title = item.findElements('name').firstOrNull?.innerText.trim() ?? '';
    out.add(
      BggCollectionEntry(
        bggId: id,
        title: title.isEmpty ? 'Sans titre' : title,
        year: int.tryParse(
          item.findElements('yearpublished').firstOrNull?.innerText.trim() ??
              '',
        ),
        imageUrl: _normalizeUrl(
          item.findElements('image').firstOrNull?.innerText,
        ),
        thumbnailUrl: _normalizeUrl(
          item.findElements('thumbnail').firstOrNull?.innerText,
        ),
        minPlayers: _positive(statAttr('minplayers')),
        maxPlayers: _positive(statAttr('maxplayers')),
        playingTime: _positive(
          statAttr('playingtime') ?? statAttr('maxplaytime'),
        ),
        isExpansion: item.getAttribute('subtype') == 'boardgameexpansion',
      ),
    );
  }
  return out;
}

class BggImportPlan {
  final List<BggCollectionEntry> toInsert;
  final List<BggCollectionEntry> alreadyOwned;
  final List<BggCollectionEntry> skippedExpansions;

  const BggImportPlan({
    required this.toInsert,
    required this.alreadyOwned,
    required this.skippedExpansions,
  });
}

String _normTitle(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Titre normalisé pour anti-doublon (import BGG, recherche partie, etc.).
String normalizeBggImportTitle(String title) => _normTitle(title);

/// Sépare les jeux à importer de ceux déjà possédés (même BGG id ou titre).
BggImportPlan planBggImport(
  Iterable<BggCollectionEntry> entries, {
  Set<String> existingBggIds = const {},
  Iterable<String> existingTitles = const [],
}) {
  final titles = existingTitles.map(normalizeBggImportTitle).toSet();
  final ids = {...existingBggIds};
  final toInsert = <BggCollectionEntry>[];
  final owned = <BggCollectionEntry>[];
  final expansions = <BggCollectionEntry>[];
  for (final e in entries) {
    if (e.bggId.isEmpty) continue;
    if (e.isExpansion) {
      expansions.add(e);
      continue;
    }
    if (ids.contains(e.bggId) ||
        titles.contains(normalizeBggImportTitle(e.title))) {
      owned.add(e);
      continue;
    }
    ids.add(e.bggId);
    titles.add(normalizeBggImportTitle(e.title));
    toInsert.add(e);
  }
  return BggImportPlan(
    toInsert: toInsert,
    alreadyOwned: owned,
    skippedExpansions: expansions,
  );
}
