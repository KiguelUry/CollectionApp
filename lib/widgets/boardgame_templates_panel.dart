import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_score_grid.dart';
import '../models/collection_item.dart';
import '../services/collection_local_cache.dart';
import '../services/community_rules_service.dart';
import '../services/community_score_templates_service.dart';
import '../services/inventory_service.dart';

/// Modèles du jeu, publication et modèles de la communauté.
class BoardgameTemplatesPanel extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;

  const BoardgameTemplatesPanel({
    super.key,
    required this.item,
    required this.readOnly,
    required this.onMetadataChanged,
  });

  @override
  State<BoardgameTemplatesPanel> createState() => _BoardgameTemplatesPanelState();
}

class _BoardgameTemplatesPanelState extends State<BoardgameTemplatesPanel> {
  List<CommunityScoreTemplate> _community = [];
  List<CommunityRuleEntry> _rules = [];
  bool _loading = true;

  String get _gameKey => CommunityRulesService.gameKeyFor(
        bggId: widget.item.metadata?['bgg_id']?.toString(),
        title: widget.item.title,
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final templates = await CommunityScoreTemplatesService.instance.forGame(_gameKey);
    final rules = await CommunityRulesService.instance.forGame(_gameKey);
    if (!mounted) return;
    setState(() {
      _community = templates;
      _rules = rules;
      _loading = false;
    });
  }

  List<NamedScorePreset> get _own =>
      NamedScorePreset.listFrom(widget.item.metadata);

  Future<void> _publish(NamedScorePreset preset) async {
    await CommunityScoreTemplatesService.instance.publish(
      gameKey: _gameKey,
      preset: preset,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('« ${preset.name} » est publié pour ce jeu')),
    );
    await _reload();
  }

  Future<void> _import(NamedScorePreset preset) async {
    final meta = Map<String, dynamic>.from(widget.item.metadata ?? {});
    final next = [
      for (final existing in _own)
        if (existing.name.toLowerCase() != preset.name.toLowerCase()) existing,
      preset,
    ];
    meta['score_presets'] = [for (final preset in next) preset.toJson()];
    widget.item.metadata
      ?..clear()
      ..addAll(meta);
    InventoryService.patchRow(widget.item.id, (row) => row['metadata'] = meta);
    await CollectionLocalCache.patchItemMetadata(widget.item.id, meta);
    try {
      await Supabase.instance.client
          .from('collection_items')
          .update({'metadata': meta}).eq('id', widget.item.id);
    } catch (_) {}
    widget.onMetadataChanged(meta);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('« ${preset.name} » ajouté à tes modèles')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final own = _own;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tes modèles', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (own.isEmpty)
          Text(
            'Aucun modèle pour ce jeu. Enregistre-en un depuis une partie.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          )
        else
          for (final preset in own) ...[
            _PreviewCard(
              title: preset.name,
              preset: preset,
              trailing: widget.readOnly
                  ? null
                  : TextButton(
                      onPressed: () => _publish(preset),
                      child: const Text('Publier'),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Text(
          'Templates de la commu',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_loading)
          const LinearProgressIndicator()
        else if (_community.isEmpty)
          Text(
            'Aucun modèle partagé pour ce jeu.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          )
        else
          for (final entry in _community) ...[
            _PreviewCard(
              title: entry.preset.name,
              subtitle: '${entry.authorName} · ${entry.likes} like${entry.likes > 1 ? 's' : ''}',
              preset: entry.preset,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Noter',
                    onPressed: () async {
                      await CommunityScoreTemplatesService.instance
                          .toggleLike(entry.id);
                      await _reload();
                    },
                    icon: Icon(
                      entry.likedByMe(
                        Supabase.instance.client.auth.currentUser?.id ?? 'local',
                      )
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                  ),
                  if (!widget.readOnly)
                    TextButton(
                      onPressed: () => _import(entry.preset),
                      child: const Text('Importer'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Text('Règles de la commu', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_rules.isEmpty)
          Text(
            'Aucune règle partagée pour ce jeu.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          )
        else
          for (final rule in _rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  title: Text(rule.title),
                  subtitle: Text(
                    '${rule.authorName} · ${rule.likes} like${rule.likes > 1 ? 's' : ''}\n${rule.body}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final NamedScorePreset preset;
  final Widget? trailing;

  const _PreviewCard({
    required this.title,
    required this.preset,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final lines = preset.template.lineNames;
    final rules = preset.template.rules;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ?trailing,
              ],
            ),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              lines.isEmpty ? 'Aucune catégorie' : lines.join(' · '),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              rules.isEmpty
                  ? 'Aucune condition de victoire'
                  : '${rules.length} condition${rules.length > 1 ? 's' : ''} · ${preset.confrontation.label}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
