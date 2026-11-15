import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_score_grid.dart';
import '../models/collection_item.dart';
import '../services/collection_local_cache.dart';
import '../screens/community_forum_screen.dart';
import '../services/community_rules_service.dart';
import '../services/community_score_templates_service.dart';
import '../services/inventory_service.dart';
import 'score_template_preview.dart';

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
    final templates =
        await CommunityScoreTemplatesService.instance.forGame(_gameKey);
    if (!mounted) return;
    setState(() => _community = templates);
  }

  List<NamedScorePreset> get _allPresets =>
      NamedScorePreset.listFrom(widget.item.metadata);

  List<NamedScorePreset> get _own =>
      _allPresets.where((preset) => !preset.imported).toList();

  List<NamedScorePreset> get _imported =>
      _allPresets.where((preset) => preset.imported).toList();

  Future<void> _publish(NamedScorePreset preset) async {
    await CommunityScoreTemplatesService.instance.publish(
      gameKey: _gameKey,
      preset: preset,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('« ${preset.name} » est partagé avec la commu')),
    );
    await _reload();
  }

  Future<void> _import(NamedScorePreset preset, String author) async {
    final label = author.trim().isEmpty
        ? preset.name
        : '${preset.name} de $author';
    final already = _allPresets.any(
      (existing) => existing.name.toLowerCase() == label.toLowerCase(),
    );
    if (already) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vous avez déjà ce template dans vos modèles.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final copy = NamedScorePreset(
      name: label,
      confrontation: preset.confrontation,
      template: preset.template,
      sourceAuthor: author,
      imported: true,
    );
    final meta = Map<String, dynamic>.from(widget.item.metadata ?? {});
    final next = [..._allPresets, copy];
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
      SnackBar(content: Text('« $label » ajouté à tes modèles')),
    );
    setState(() {});
  }

  void _openPreview(NamedScorePreset preset) {
    showScoreTemplatePreview(
      context,
      preset: preset,
      gameTitle: widget.item.title,
    );
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
              onTap: () => _openPreview(preset),
              trailing: widget.readOnly
                  ? null
                  : TextButton(
                      onPressed: () => _publish(preset),
                      child: const Text('Partager avec la commu'),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Text(
          'Templates de la commu importés',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_imported.isEmpty)
          Text(
            'Aucun modèle importé.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          )
        else
          for (final preset in _imported) ...[
            _PreviewCard(
              title: preset.name,
              preset: preset,
              onTap: () => _openPreview(preset),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityForumScreen(
                  gameKey: _gameKey,
                  gameTitle: widget.item.title,
                  item: widget.item,
                  onImportTemplate: (preset) {
                    var author = 'la commu';
                    for (final entry in _community) {
                      if (entry.preset.name == preset.name) {
                        author = entry.authorName;
                        break;
                      }
                    }
                    _import(preset, author);
                  },
                ),
              ),
            );
          },
          icon: const Text('🌍'),
          label: const Text('Explorer le Forum des Templates de ce jeu'),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String title;
  final NamedScorePreset preset;
  final Widget? trailing;
  final VoidCallback onTap;

  const _PreviewCard({
    required this.title,
    required this.preset,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in preset.template.lineNames)
                    ScoreCategoryChip(name: name, compact: true),
                ],
              ),
              const SizedBox(height: 8),
              ScoreRuleBadges(template: preset.template, compact: true),
              const SizedBox(height: 4),
              Text(
                preset.confrontation.label,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
