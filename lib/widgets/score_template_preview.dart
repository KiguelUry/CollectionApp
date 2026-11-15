import 'package:flutter/material.dart';

import '../models/boardgame_score_grid.dart';

/// Pastille catégorie propre (sans point radio gris).
class ScoreCategoryChip extends StatelessWidget {
  final String name;
  final bool compact;

  const ScoreCategoryChip({
    super.key,
    required this.name,
    this.compact = false,
  });

  static Color accentFor(String name) {
    final n = name.toLowerCase().trim();
    if (n.contains('mercure')) return const Color(0xFF9E9E9E);
    if (n.contains('vénus') || n.contains('venus')) {
      return const Color(0xFFFFC107);
    }
    if (n.contains('terre') || n.contains('earth')) {
      return const Color(0xFF42A5F5);
    }
    if (n.contains('mars')) return const Color(0xFFE53935);
    if (n.contains('jupiter')) return const Color(0xFF8D6E63);
    if (n.contains('saturne')) return const Color(0xFFFFB74D);
    if (n.contains('uranus')) return const Color(0xFF26C6DA);
    if (n.contains('neptune')) return const Color(0xFF5C6BC0);
    final hash = n.hashCode;
    final hues = <Color>[
      const Color(0xFF66BB6A),
      const Color(0xFFAB47BC),
      const Color(0xFF29B6F6),
      const Color(0xFFFF7043),
      const Color(0xFF26A69A),
    ];
    return hues[hash.abs() % hues.length];
  }

  static String emojiFor(String name) {
    final n = name.toLowerCase().trim();
    if (n.contains('mercure')) return '⚫️';
    if (n.contains('vénus') || n.contains('venus')) return '🟡';
    if (n.contains('terre') || n.contains('earth')) return '🌍';
    if (n.contains('mars')) return '🔴';
    if (n.contains('jupiter')) return '🟤';
    if (n.contains('saturne')) return '🪐';
    return '🔘';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentFor(name);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emojiFor(name), style: TextStyle(fontSize: compact ? 11 : 13)),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badges de conditions de victoire séparés.
class ScoreRuleBadges extends StatelessWidget {
  final BoardgameScoreTemplate template;
  final bool compact;

  const ScoreRuleBadges({
    super.key,
    required this.template,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (template.rules.isEmpty) {
      return Text(
        'Aucune condition',
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final children = <Widget>[];
    for (var i = 0; i < template.rules.length; i++) {
      if (i > 0) {
        final join = template.rules[i].link ??
            (template.matchAll ? ScoreRuleJoin.and : ScoreRuleJoin.or);
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              join == ScoreRuleJoin.and ? 'ET' : 'OU',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
        );
      }
      children.add(
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            template.rules[i].phrase,
            style: TextStyle(
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// Mini-grille visuelle d'exemple (catégories × joueurs).
class ScoreTemplateMiniGrid extends StatelessWidget {
  final BoardgameScoreTemplate template;
  final int players;

  const ScoreTemplateMiniGrid({
    super.key,
    required this.template,
    this.players = 2,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = template.lineNames;
    if (lines.isEmpty) {
      return Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Pas de catégories',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final cols = players.clamp(1, 3);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 54),
              for (var p = 1; p <= cols; p++)
                Expanded(
                  child: Text(
                    'J$p',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final line in lines.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: ScoreCategoryChip.accentFor(line),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (var p = 0; p < cols; p++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: scheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          '${(p + 1) * (line.length % 3 + 1)}',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showScoreTemplatePreview(
  BuildContext context, {
  required NamedScorePreset preset,
  String? gameTitle,
  String? authorName,
  VoidCallback? onImport,
  Future<void> Function()? onUnpublish,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                preset.name,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if ((gameTitle ?? '').isNotEmpty ||
                  (authorName ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if ((gameTitle ?? '').isNotEmpty) gameTitle!,
                    if ((authorName ?? '').isNotEmpty) authorName!,
                  ].join(' · '),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Mode : ${preset.confrontation.label}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Catégories',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in preset.template.lineNames)
                    ScoreCategoryChip(name: name),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Conditions de victoire',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              ScoreRuleBadges(template: preset.template),
              const SizedBox(height: 14),
              Text(
                'Exemple de tableau',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              ScoreTemplateMiniGrid(template: preset.template, players: 3),
              const SizedBox(height: 16),
              if (onImport != null)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onImport();
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Importer dans mes templates'),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fermer'),
                ),
              if (onUnpublish != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await onUnpublish();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Retirer du forum'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
