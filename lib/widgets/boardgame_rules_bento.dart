import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_item.dart';
import '../models/rule_section.dart';
import '../services/community_rules_service.dart';
import 'detail_bento_tile.dart';
import 'modular_rule_editor.dart';

enum _RulesSub { none, create, display, community }

/// Bento « Règles » : perso, affichage, communauté.
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
  _RulesSub _sub = _RulesSub.none;
  List<CommunityRuleEntry> _community = [];
  List<CommunityRuleEntry> _pinned = [];
  String? _langFilter;
  bool _loadingCommu = false;

  String get _gameKey => CommunityRulesService.gameKeyFor(
        bggId: widget.item.metadata?['bgg_id']?.toString(),
        title: widget.item.title,
      );

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
    _loadCommunity();
  }

  @override
  void didUpdateWidget(BoardgameRulesBento oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _sections = RuleBodyCodec.decode(widget.item.personalRules ?? '');
      _sub = _RulesSub.none;
      _loadCommunity();
    }
  }

  Future<void> _loadCommunity() async {
    setState(() => _loadingCommu = true);
    final svc = CommunityRulesService.instance;
    final list = await svc.forGame(_gameKey, language: _langFilter);
    final pinned = await svc.pinnedForItem(widget.item.id);
    if (!mounted) return;
    setState(() {
      _community = list;
      _pinned = pinned;
      _loadingCommu = false;
    });
  }

  String get _subtitle {
    final filled = _sections
        .where((s) => s.plainText.trim().isNotEmpty || s.imageUrl != null)
        .length;
    final total = filled + _pinned.length;
    if (total <= 0) return 'Aucune règle';
    final parts = <String>[];
    if (filled > 0) {
      parts.add(
        '$filled perso',
      );
    }
    if (_pinned.isNotEmpty) {
      parts.add(
        '${_pinned.length} affichée${_pinned.length > 1 ? 's' : ''}',
      );
    }
    return parts.join(' · ');
  }

  void _onSectionsChanged(List<RuleSection> next) {
    setState(() => _sections = next);
    final encoded =
        RuleBodyCodec.isEmpty(next) ? '' : RuleBodyCodec.encode(next);
    widget.onPersonalRulesChanged(encoded);
  }

  void _select(_RulesSub sub) {
    setState(() => _sub = _sub == sub ? _RulesSub.none : sub);
  }

  Future<void> _publishPersonal() async {
    final encoded = RuleBodyCodec.encode(_sections);
    if (RuleBodyCodec.isEmpty(_sections)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Écris d\'abord tes règles perso')),
      );
      return;
    }
    final lang = await _pickLanguage();
    if (lang == null || !mounted) return;
    await CommunityRulesService.instance.publish(
      gameKey: _gameKey,
      language: lang,
      title: 'Règles de ${widget.item.title}',
      body: encoded,
    );
    await _loadCommunity();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Règles publiées pour la communauté')),
    );
  }

  Future<String?> _pickLanguage() async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Langue de tes règles'),
              subtitle: Text('Aide les autres à filtrer'),
            ),
            for (final e in const [
              ('fr', 'Français'),
              ('en', 'English'),
              ('nl', 'Nederlands'),
              ('de', 'Deutsch'),
              ('es', 'Español'),
              ('it', 'Italiano'),
            ])
              ListTile(
                title: Text(e.$2),
                onTap: () => Navigator.pop(ctx, e.$1),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pinCommunityRule(String id) async {
    await CommunityRulesService.instance.pinToItem(widget.item.id, id);
    await _loadCommunity();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ajoutée à « Afficher les règles »'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.orange.shade800;

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
          DetailBentoSubTile(
            icon: Icons.edit_note_outlined,
            title: 'Créer mes règles',
            subtitle: RuleBodyCodec.isEmpty(_sections)
                ? 'Objectif, mise en place, tour…'
                : 'Modifier ton résumé',
            accent: accent,
            selected: _sub == _RulesSub.create,
            onTap: () => _select(_RulesSub.create),
          ),
          const SizedBox(height: 8),
          DetailBentoSubTile(
            icon: Icons.visibility_outlined,
            title: 'Afficher les règles',
            subtitle: _pinned.isEmpty
                ? (RuleBodyCodec.isEmpty(_sections)
                    ? 'Perso + règles ajoutées'
                    : 'Ton résumé')
                : '${_pinned.length} règle${_pinned.length > 1 ? 's' : ''} affichée${_pinned.length > 1 ? 's' : ''}',
            accent: accent,
            selected: _sub == _RulesSub.display,
            onTap: () => _select(_RulesSub.display),
          ),
          const SizedBox(height: 8),
          DetailBentoSubTile(
            icon: Icons.forum_outlined,
            title: 'Règles de la commu',
            subtitle: _community.isEmpty
                ? 'Publier · liker · filtrer par langue'
                : '${_community.length} publiée${_community.length > 1 ? 's' : ''}',
            accent: accent,
            selected: _sub == _RulesSub.community,
            onTap: () => _select(_RulesSub.community),
          ),
          if (_sub != _RulesSub.none) ...[
            const SizedBox(height: 14),
            switch (_sub) {
              _RulesSub.create => _CreateBody(
                  sections: _sections,
                  readOnly: widget.readOnly,
                  onChanged: _onSectionsChanged,
                  onPublish: widget.readOnly ? null : _publishPersonal,
                ),
              _RulesSub.display => _DisplayBody(
                  sections: _sections,
                  pinned: _pinned,
                  onUnpin: (id) async {
                    await CommunityRulesService.instance
                        .unpinFromItem(widget.item.id, id);
                    await _loadCommunity();
                  },
                ),
              _RulesSub.community => _CommunityBody(
                  loading: _loadingCommu,
                  entries: _community,
                  langFilter: _langFilter,
                  userId: Supabase.instance.client.auth.currentUser?.id,
                  onFilter: (lang) {
                    setState(() => _langFilter = lang);
                    _loadCommunity();
                  },
                  onLike: (id) async {
                    await CommunityRulesService.instance.toggleLike(id);
                    await _loadCommunity();
                  },
                  onAdd: _pinCommunityRule,
                  onPublish: widget.readOnly ? null : _publishPersonal,
                ),
              _RulesSub.none => const SizedBox.shrink(),
            },
          ],
        ],
      ),
    );
  }
}

class _CreateBody extends StatelessWidget {
  final List<RuleSection> sections;
  final bool readOnly;
  final ValueChanged<List<RuleSection>> onChanged;
  final VoidCallback? onPublish;

  const _CreateBody({
    required this.sections,
    required this.readOnly,
    required this.onChanged,
    this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Écris le déroulé à ta sauce : objectif, mise en place, tour de jeu…',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (readOnly)
          _ReadOnlySections(sections: sections)
        else
          ModularRuleEditor(
            initialSections: sections,
            onChanged: onChanged,
          ),
        if (onPublish != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPublish,
            icon: const Icon(Icons.public, size: 18),
            label: const Text('Publier pour la communauté'),
          ),
        ],
      ],
    );
  }
}

class _DisplayBody extends StatelessWidget {
  final List<RuleSection> sections;
  final List<CommunityRuleEntry> pinned;
  final ValueChanged<String> onUnpin;

  const _DisplayBody({
    required this.sections,
    required this.pinned,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPerso = !RuleBodyCodec.isEmpty(sections);
    if (!hasPerso && pinned.isEmpty) {
      return Text(
        'Aucune règle à afficher. Crée ton résumé ou ajoute une règle commu.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasPerso) ...[
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Mes règles',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ReadOnlySections(sections: sections),
        ],
        for (final e in pinned) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Chip(
                label: const Text('Commu'),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 11),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onUnpin(e.id),
              ),
            ],
          ),
          _ReadOnlySections(sections: RuleBodyCodec.decode(e.body)),
        ],
      ],
    );
  }
}

class _CommunityBody extends StatelessWidget {
  final bool loading;
  final List<CommunityRuleEntry> entries;
  final String? langFilter;
  final String? userId;
  final ValueChanged<String?> onFilter;
  final ValueChanged<String> onLike;
  final ValueChanged<String> onAdd;
  final VoidCallback? onPublish;

  const _CommunityBody({
    required this.loading,
    required this.entries,
    required this.langFilter,
    required this.userId,
    required this.onFilter,
    required this.onLike,
    required this.onAdd,
    this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('Toutes'),
              selected: langFilter == null,
              onSelected: (_) => onFilter(null),
            ),
            for (final e in const [
              ('fr', 'FR'),
              ('en', 'EN'),
              ('nl', 'NL'),
              ('de', 'DE'),
            ])
              FilterChip(
                label: Text(e.$2),
                selected: langFilter == e.$1,
                onSelected: (_) => onFilter(e.$1),
              ),
          ],
        ),
        if (onPublish != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPublish,
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Publier mes règles'),
          ),
        ],
        const SizedBox(height: 10),
        if (loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (entries.isEmpty)
          Text(
            'Pas encore de règles publiées pour ce jeu. Sois le premier !',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else
          for (final e in entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          e.language.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'par ${e.authorName} · ${e.likes} like${e.likes > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => onLike(e.id),
                          icon: Icon(
                            e.likedByMe(userId)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                          ),
                          label: const Text('Liker'),
                        ),
                        TextButton.icon(
                          onPressed: () => onAdd(e.id),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
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
