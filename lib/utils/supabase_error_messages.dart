/// Messages utilisateur pour erreurs Supabase / Auth (évite le dump technique).
String humanizeSupabaseError(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('exceed_egress_quota') ||
      (lower.contains('402') && lower.contains('restricted')) ||
      (lower.contains('usage') && lower.contains('quota'))) {
    return 'Service momentanément indisponible\n\n'
        'L’application a atteint sa capacité technique maximale. '
        'Le service revient automatiquement. Réessaie dans un moment.';
  }

  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid_credentials')) {
    return 'E-mail ou mot de passe incorrect.';
  }

  if (lower.contains('email_address_invalid') ||
      (lower.contains('email address') && lower.contains('invalid'))) {
    return 'Cette adresse e-mail n’est pas valide.';
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
