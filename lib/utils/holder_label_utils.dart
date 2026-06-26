/// Préfixe adapté pour un lieu ou une personne (« Chez », « En », « Au », « À »).
String formatManualHolderLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  if (RegExp(r'^(chez|en|au|à|a)\s+', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  final lower = trimmed.toLowerCase();
  const enPlaces = {
    'croatie', 'france', 'espagne', 'italie', 'allemagne', 'belgique',
    'suisse', 'autriche', 'pologne', 'irlande', 'angleterre', 'écosse',
    'norvège', 'suède', 'finlande', 'grèce', 'turquie', 'chine', 'inde',
    'australie', 'argentine', 'algérie', 'maroc', 'tunisie', 'égypte',
  };
  const auPlaces = {
    'canada', 'portugal', 'japon', 'mexique', 'brésil', 'brasil', 'chili',
    'pérou', 'perou', 'pakistan', 'vietnam', 'cambodge', 'laos',
  };
  const aPlaces = {
    'paris', 'lyon', 'marseille', 'londres', 'berlin', 'madrid', 'rome',
    'barcelone', 'bruxelles', 'genève', 'zurich', 'montréal', 'montreal',
    'braine', 'namur', 'liège', 'liege', 'charleroi', 'gand', 'anvers',
  };

  String cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  if (enPlaces.contains(lower)) return 'En ${cap(trimmed)}';
  if (auPlaces.contains(lower)) return 'Au ${cap(trimmed)}';
  if (aPlaces.contains(lower)) return 'À ${cap(trimmed)}';

  final looksLikePlace = RegExp(
    r'\b(ville|pays|région|region|maison|appart|studio|loft|cave|grenier|garage|bureau|école|ecole|université|universite)\b',
    caseSensitive: false,
  ).hasMatch(trimmed);

  if (looksLikePlace || trimmed.contains('-') || trimmed.contains(',')) {
    return 'À $trimmed';
  }

  return 'Chez ${cap(trimmed)}';
}

/// Valeur brute stockée en metadata (sans préfixe).
String holderLabelStorageValue(String displayLabel) {
  return displayLabel.replaceFirst(
    RegExp(r'^(Chez|En|Au|À|A)\s+', caseSensitive: false),
    '',
  );
}
