/// Type d’alerte affichée sur le hub principal.
enum CollectionInsightKind {
  warranty,
  loan,
  tcg,
  books,
}

/// Insight transversal (garanties, prêts, complétion…).
class CollectionInsight {
  final CollectionInsightKind kind;
  final String message;
  final String? actionLabel;

  const CollectionInsight({
    required this.kind,
    required this.message,
    this.actionLabel,
  });
}
