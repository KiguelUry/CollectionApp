/// IDs BGG par genre — amorces pour le fetch, puis filtre sur les vraies catégories BGG.
const Map<String, List<String>> boardgameCuratedIdsByGenre = {
  'Strategy': [
    '224517', '161936', '167791', '266192', '342942', '162886', '182028',
    '169786', '124361', '120677', '291457', '205637', '187645', '164928',
    '72125', '266810', '236457', '193738', '341169', '175914', '199792',
    '155821', '163068', '62219', '35677', '110327', '7854', '82222',
    '31260', '174430',
  ],
  'Family': [
    '13', '9209', '68448', '172386', '178900', '188920', '822', '140934',
    '266524', '39856', '156546', '54043', '129622', '295947', '298047',
    '283155', '244521', '30549', '196340', '70323', '384213', '218417',
    '314491', '367220', '271324', '199561', '230253', '254386', '286096',
    '365717',
  ],
  'Party': [
    '178900', '39856', '2664', '99316', '181304', '153065', '89325',
    '156546', '129622', '54043', '17133', '822', '188920', '148228',
    '171499', '163412', '193037', '199561', '254386', '286096',
  ],
  'Cooperative': [
    '167791', '266192', '182028', '169786', '124361', '120677', '291457',
    '205637', '187645', '164928', '72125', '30549', '196340', '162886',
    '342942', '236457', '193738', '341169', '175914', '199792', '266810',
  ],
  'Card Game': [
    '172386', '68448', '9209', '13', '178900', '266524', '199792', '291457',
    '156546', '129622', '54043', '171499', '163412', '193037', '199561',
    '254386', '286096', '384213', '218417',
  ],
  'Economic': [
    '224517', '174430', '31260', '182028', '169786', '124361', '120677',
    '291457', '205637', '187645', '164928', '72125', '266810', '236457',
    '193738', '341169', '175914', '199792', '62219', '35677', '110327',
  ],
  'Adventure': [
    '167791', '266192', '182028', '169786', '124361', '120677', '291457',
    '205637', '187645', '164928', '72125', '266810', '236457', '193738',
    '341169', '175914', '199792', '342942', '162886',
  ],
  'Abstract': [
    '140934', '68448', '172386', '13', '9209', '148228', '17133', '822',
    '2664', '99316', '181304', '384213', '218417', '314491', '367220',
  ],
};

const boardgameGlobalTopIds = [
  '224517', '161936', '174430', '167791', '266192', '31260', '182028',
  '169786', '12333', '68448', '173346', '13', '9209', '172386', '230802',
  '266524', '185343', '124361', '120677', '291457', '205637', '187645',
  '164928', '72125', '148228', '266810', '236457', '193738', '341169',
  '175914', '199792', '256960', '162886', '155821', '163068', '62219',
  '35677', '70323', '110327', '7854', '342942', '140934', '178900',
];

/// Catégories BGG acceptées par tuile « genre » de l'app.
const Map<String, List<String>> boardgameGenreBggCategories = {
  'Strategy': ['Strategy', 'Wargame'],
  'Family': ['Family', "Children's Game"],
  'Party': ['Party Game', 'Humor'],
  'Cooperative': ['Cooperative Game'],
  'Card Game': ['Card Game'],
  'Economic': ['Economic', 'Industry / Manufacturing'],
  'Adventure': ['Adventure', 'Exploration', 'Fantasy', 'Fighting'],
  'Abstract': ['Abstract Strategy', 'Abstract'],
  'Deduction': ['Deduction', 'Mystery'],
  'Fantasy': ['Fantasy'],
  'Science Fiction': ['Science Fiction', 'Space Exploration'],
  'Horror': ['Horror'],
  'Wargame': ['Wargame'],
  'Humor': ['Humor'],
  'Negotiation': ['Negotiation'],
  'Racing': ['Racing'],
  'Puzzle': ['Puzzle'],
  'Medieval': ['Medieval', 'Renaissance'],
  'Miniatures': ['Miniatures'],
  'Trains': ['Trains', 'Transportation'],
  'Zombies': ['Zombies'],
  'Trivia': ['Trivia'],
  'Real-time': ['Real-time'],
  'Exploration': ['Exploration'],
};

List<String> curatedIdsForGenre(String genreEn, {int max = 80}) {
  const aliases = {
    'Thematic': 'Adventure',
    'Wargame': 'Strategy',
    "Children's Game": 'Family',
  };
  final key = aliases[genreEn] ?? genreEn;
  final ids = boardgameCuratedIdsByGenre[key] ?? boardgameGlobalTopIds;
  return ids.take(max).toList();
}

bool boardgameMapMatchesGenre(
  Map<String, String> map,
  String genreEn, {
  Set<String>? allowedIds,
}) {
  final id = map['id'] ?? '';
  if (allowedIds != null && allowedIds.contains(id)) return true;

  final allowed = boardgameGenreBggCategories[genreEn];
  final raw = map['bgg_categories'] ?? '';

  if (raw.isEmpty) {
    // Sans catégories BGG : on ne garde que les IDs curés pour ce genre.
    return allowedIds == null || allowedIds.contains(id);
  }

  if (allowed == null || allowed.isEmpty) return true;

  final cats = raw.split('|').map((s) => s.trim().toLowerCase()).toSet();
  for (final a in allowed) {
    if (cats.contains(a.toLowerCase())) return true;
  }
  return false;
}
