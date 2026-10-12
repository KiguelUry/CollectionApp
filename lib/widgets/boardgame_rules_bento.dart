import 'package:flutter/material.dart';

import '../models/collection_item.dart';
import '../models/rule_section.dart';
import 'detail_bento_tile.dart';
import 'group_rules_panel.dart';
import 'modular_rule_editor.dart';

/// Bento « Règles » : perso (sections modulaires) + variantes de groupe.
class BoardgameRulesBento extends StatefulWidget {
  final CollectionItem item;
  final bool readOnly;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onPersonalRulesChanged;

  const BoardgameRulesBento({
    super.key,
    required this.item,
    required this.readOnly,
    required this.expanded,
    required this.onToggle,
    required this.onPersonalRulesChanged,
  });

  @override
  State<BoardgameRulesBento> createState() => _BoardgameRulesBentoState();
}

class _BoardgameRulesBentoState extends State<BoardgameRulesBento> {
  late List<RuleSection> _sections;
  var _tab = 0; // 0 perso · 1 groupe

  @override
  void initState() {
    super.initState();
    _sections = RuleBodyCodec.decode(widget.item.personalRules ?? '');
    if (_sections.isEmpty) {
      _sections = [
        RuleSection(id: 'obj', kind: RuleSectionKind.objective),
        RuleSection(id: 'setup', kind: RuleSectionKind.setup),
        RuleSection(id: 'summary', kind: RuleSectionKind.summary),
      ];
    }
    if (widget.item.groupId != null) _tab = 1;
  }

  @override
  void didUpdateWidget(BoardgameRulesBento oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recharger seulement si on change d'objet (pas à chaque save local).
    if (oldWidget.item.id != widget.item.id) {
      _sections = RuleBodyCodec.decode(widget.item.personalRules ?? '');
      _tab = widget.item.groupId != null ? 1 : 0;
    }
  }

  String get _subtitle {
    final hasPerso = !RuleBodyCodec.isEmpty(_sections);
    if (widget.item.groupId != null) {
      return hasPerso
          ? 'Perso + variantes du groupe'
          : 'Variantes partagées du groupe';
    }
    return hasPerso
        ? 'Objectif, mise en place, tour…'
        : 'Sections modulaires (perso)';
  }

  void _onSectionsChanged(List<RuleSection> next) {
    setState(() => _sections = next);
    final encoded = RuleBodyCodec.isEmpty(next) ? '' : RuleBodyCodec.encode(next);
    widget.onPersonalRulesChanged(encoded);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.orange.shade800;
    final hasGroup = widget.item.groupId != null;

    return DetailBentoTile(
      icon: Icons.menu_book_outlined,
      title: 'Règles',
      subtitle: _subtitle,
      accent: accent,
      expanded: widget.expanded,
      onTap: widget.onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasGroup) ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Perso'),
                  icon: Icon(Icons.person_outline, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Groupe'),
                  icon: Icon(Icons.groups_outlined, size: 16),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 12),
          ],
          if (!hasGroup || _tab == 0) ...[
            Text(
              'Tes notes de règles — sections proposées, tu peux en ajouter ou en retirer.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (widget.readOnly)
              _ReadOnlySections(sections: _sections)
            else
              ModularRuleEditor(
                initialSections: _sections,
                onChanged: _onSectionsChanged,
              ),
          ] else
            GroupRulesPanel(
              groupId: widget.item.groupId!,
              itemId: widget.item.id,
              itemTitle: widget.item.title,
              accent: accent,
            ),
        ],
      ),
    );
  }
}

class _ReadOnlySections extends StatelessWidget {
  final List<RuleSection> sections;

  const _ReadOnlySections({required this.sections});

  @override
  Widget build(BuildContext context) {
    if (RuleBodyCodec.isEmpty(sections)) {
      return Text(
        'Aucune règle personnelle.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in sections)
          if (s.plainText.trim().isNotEmpty) ...[
            Text(
              s.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(s.plainText),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}
