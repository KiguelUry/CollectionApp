/// Messages utilisateur pour erreurs Supabase / Auth (évite le dump technique).
String humanizeSupabaseError(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('exceed_egress_quota') ||
      (lower.contains('402') && lower.contains('restricted')) ||
      (lower.contains('usage') && lower.contains('quota'))) {
    return 'Le projet Supabase a dépassé le quota de bande passante '
        'du plan gratuit.\n\n'
        'Les connexions sont temporairement suspendues jusqu’au '
        'renouvellement du quota (prévu autour du 10 novembre).\n\n'
        'Ce n’est pas un problème de mot de passe : réessaie après cette date.';
  }

  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid_credentials')) {
    return 'E-mail ou mot de passe incorrect.';
  }

  if (lower.contains('email not confirmed')) {
    return 'Confirme d’abord ton adresse e-mail (lien reçu à l’inscription).';
  }

  if (lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup')) {
    return 'Pas de connexion réseau. Vérifie ta connexion puis réessaie.';
  }

  // Garde un extrait court si message déjà lisible, sinon raw tronqué.
  final cleaned = raw
      .replaceFirst(RegExp(r'^.*?Exception:\s*'), '')
      .replaceFirst(RegExp(r'^AuthApiException\(message:\s*'), '')
      .trim();
  if (cleaned.length <= 280) return cleaned;
  return '${cleaned.substring(0, 277)}…';
}
