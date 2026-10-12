import 'package:flutter/material.dart';

/// Tuile bento expansible pour la fiche détail.
class DetailBentoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final bool expanded;
  final VoidCallback onTap;
  final Widget? child;
  final bool compact;

  const DetailBentoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.expanded,
    required this.onTap,
    this.subtitle,
    this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: expanded
              ? accent.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 64 : 76),
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 14,
                compact ? 10 : 12,
                10,
                compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: expanded
                      ? accent.withValues(alpha: 0.55)
                      : scheme.outlineVariant.withValues(alpha: 0.3),
                  width: expanded ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: compact ? 22 : 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 14 : 15,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded && child != null) ...[
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: child!,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Sous-tuile à l’intérieur d’un hub bento (ex. Parties → Stats / Historique).
class DetailBentoSubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const DetailBentoSubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.18)
          : scheme.surface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.5)
                  : scheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.expand_less : Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
