import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_score_grid.dart';
import '../models/collection_item.dart';
import '../models/rule_section.dart';
import '../services/community_rules_service.dart';
import '../services/community_score_templates_service.dart';
import '../services/profile_cache_service.dart';
import '../widgets/modular_rule_editor.dart';

enum ForumKind { templates, rules, contributors }

class CommunityForumScreen extends StatefulWidget {
  final String? gameKey;
  final String? gameTitle;
  final ForumKind initialKind;
  final CollectionItem? item;
  final ValueChanged<NamedScorePreset>? onImportTemplate;

  const CommunityForumScreen({
    super.key,
    this.gameKey,
    this.gameTitle,
    this.initialKind = ForumKind.templates,
    this.item,
    this.onImportTemplate,
  });

  @override
  State<CommunityForumScreen> createState() => _CommunityForumScreenState();
}

class _CommunityForumScreenState extends State<CommunityForumScreen> {
  ForumKind _kind = ForumKind.templates;
  String _sort = 'likes';
  String? _gameKey;
  String? _gameTitle;
  bool _monthOnly = false;
  bool _mineOnly = false;
  String _search = '';
  List<CommunityScoreTemplate> _templates = [];
  List<CommunityRuleEntry> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _gameKey = widget.gameKey;
    _gameTitle = widget.gameTitle;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final templates = await CommunityScoreTemplatesService.instance.all();
    final rules = await CommunityRulesService.instance.all();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _rules = rules;
      _loading = false;
    });
  }

  List<String> get _gameKeys {
    final keys = <String>{
      for (final template in _templates) template.gameKey,
      for (final rule in _rules) rule.gameKey,
      ?_gameKey,
      ?widget.gameKey,
    };
    return keys.toList()..sort();
  }

  String get _title {
    if (_gameKey == null) return 'Forum communautaire';
    return 'Forum · ${_gameLabel(_gameKey!)}';
  }

  String _gameLabel(String key) {
    if (_gameKey == key && (_gameTitle ?? '').trim().isNotEmpty) {
      return _gameTitle!.trim();
    }
    if (widget.gameKey == key && (widget.gameTitle ?? '').trim().isNotEmpty) {
      return widget.gameTitle!.trim();
    }
    if (key.startsWith('title:')) {
      final raw = key.substring(6).trim();
      if (raw.isEmpty) return key;
      return raw[0].toUpperCase() + raw.substring(1);
    }
    if (key.startsWith('bgg:')) return 'BGG ${key.substring(4)}';
    return key;
  }

  bool _matchesSearch(String haystack) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return haystack.toLowerCase().contains(q);
  }

  String? get _meId =>
      Supabase.instance.client.auth.currentUser?.id ?? 'local';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_gameKey != null)
            IconButton(
              tooltip: 'Tous les jeux',
              onPressed: () => setState(() {
                _gameKey = null;
                _gameTitle = null;
              }),
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: 'Partager',
            onPressed: _share,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _share,
        icon: const Icon(Icons.add),
        label: const Text('Partager'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _ForumTabs(
              kind: _kind,
              onChanged: (k) => setState(() {
                _kind = k;
                if (k != ForumKind.contributors) _monthOnly = false;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: _FilterBar(
              gameKeys: _gameKeys,
              gameKey: _gameKey,
              gameLabelOf: _gameLabel,
              sort: _sort,
              mineOnly: _mineOnly,
              monthOnly: _monthOnly,
              showSort: _kind != ForumKind.contributors,
              showMonth: _kind == ForumKind.contributors,
              search: _search,
              onSearch: (v) => setState(() => _search = v),
              onGameKey: (key, title) => setState(() {
                _gameKey = key;
                _gameTitle = title;
              }),
              onSort: (s) => setState(() => _sort = s),
              onMineOnly: (v) => setState(() => _mineOnly = v),
              onMonthOnly: (v) => setState(() => _monthOnly = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _kind == ForumKind.templates
                        ? _buildTemplates(scheme)
                        : _kind == ForumKind.rules
                            ? _buildRules(scheme)
                            : _buildContributors(scheme),
                  ),
          ),
        ],
      ),
    );
  }

  List<CommunityScoreTemplate> _filteredTemplates() {
    final me = _meId;
    final list = [
      for (final entry in _templates)
        if ((_gameKey == null || entry.gameKey == _gameKey) &&
            (!_mineOnly || entry.authorId == me) &&
            _matchesSearch(
              '${entry.preset.name} ${entry.authorName} ${_gameLabel(entry.gameKey)}',
            ))
          entry,
    ];
    final points = _authorPoints(forMonth: false);
    list.sort((a, b) {
      if (_sort == 'recent') return b.createdAt.compareTo(a.createdAt);
      if (_sort == 'author') {
        return (points[b.authorId] ?? 0).compareTo(points[a.authorId] ?? 0);
      }
      return b.likes.compareTo(a.likes);
    });
    return list;
  }

  List<CommunityRuleEntry> _filteredRules() {
    final me = _meId;
    final list = [
      for (final entry in _rules)
        if ((_gameKey == null || entry.gameKey == _gameKey) &&
            (!_mineOnly || entry.authorId == me) &&
            _matchesSearch(
              '${entry.title} ${entry.authorName} ${_gameLabel(entry.gameKey)}',
            ))
          entry,
    ];
    final points = _authorPoints(forMonth: false);
    list.sort((a, b) {
      if (_sort == 'recent') return b.createdAt.compareTo(a.createdAt);
      if (_sort == 'author') {
        return (points[b.authorId] ?? 0).compareTo(points[a.authorId] ?? 0);
      }
      return b.likes.compareTo(a.likes);
    });
    return list;
  }

  Widget _buildTemplates(ColorScheme scheme) {
    final list = _filteredTemplates();
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Aucun template pour ce filtre.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonal(
              onPressed: _share,
              child: const Text('Partager un template'),
            ),
          ),
        ],
      );
    }
    return _BentoGrid(
      children: [
        for (final entry in list)
          _TemplateCard(
            entry: entry,
            gameLabel: _gameLabel(entry.gameKey),
            thumb: _thumb(entry.gameKey),
            badge: _rankBadge(_authorPoints(forMonth: false)[entry.authorId] ?? 0),
            liked: entry.likedByMe(_meId),
            onAuthor: () => _openContributor(entry.authorId, entry.authorName),
            onOpen: () => _openTemplate(entry),
            onLike: () async {
              await CommunityScoreTemplatesService.instance.toggleLike(entry.id);
              await _load();
            },
            onImport: () => _importTemplate(entry),
          ),
      ],
    );
  }

  Widget _buildRules(ColorScheme scheme) {
    final list = _filteredRules();
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Aucune règle pour ce filtre.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    return _BentoGrid(
      children: [
        for (final entry in list)
          _RuleCard(
            entry: entry,
            gameLabel: _gameLabel(entry.gameKey),
            thumb: _thumb(entry.gameKey),
            badge: _rankBadge(_authorPoints(forMonth: false)[entry.authorId] ?? 0),
            liked: entry.likedByMe(_meId),
            excerpt: _ruleExcerpt(entry.body),
            onAuthor: () => _openContributor(entry.authorId, entry.authorName),
            onOpen: () => _openRule(entry),
            onLike: () async {
              await CommunityRulesService.instance.toggleLike(entry.id);
              await _load();
            },
          ),
      ],
    );
  }

  Widget _buildContributors(ColorScheme scheme) {
    final stats = _contributorStats();
    if (stats.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Aucun contributeur pour l\'instant.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    final podium = stats.take(3).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      children: [
        if (podium.isNotEmpty) ...[
          Text(
            'Podium',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < podium.length; i++)
                Expanded(
                  child: _PodiumTile(
                    place: i + 1,
                    name: podium[i].name,
                    likes: podium[i].likes,
                    badge: _rankBadge(podium[i].likes),
                    onTap: () =>
                        _openContributor(podium[i].id, podium[i].name),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Classement',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < stats.length; i++)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              child: Text('${i + 1}'),
            ),
            title: Text(
              stats[i].name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${stats[i].likes} likes · ${stats[i].templates} templates · ${stats[i].rules} règles · ${_rankBadge(stats[i].likes)}',
            ),
            onTap: () => _openContributor(stats[i].id, stats[i].name),
          ),
      ],
    );
  }

  Widget _thumb(String gameKey) {
    final url = (widget.gameKey == gameKey || _gameKey == gameKey)
        ? widget.item?.imageUrl
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null || url.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.casino_outlined, size: 20),
              )
            : Image.network(url, fit: BoxFit.cover),
      ),
    );
  }

  Map<String, int> _authorPoints({required bool forMonth}) {
    final points = <String, int>{};
    bool keep(DateTime date) {
      if (!forMonth || !_monthOnly) return true;
      final now = DateTime.now();
      return date.year == now.year && date.month == now.month;
    }

    for (final entry in _templates) {
      if (!keep(entry.createdAt)) continue;
      if (_gameKey != null && entry.gameKey != _gameKey) continue;
      points[entry.authorId] = (points[entry.authorId] ?? 0) + entry.likes;
    }
    for (final entry in _rules) {
      if (!keep(entry.createdAt)) continue;
      if (_gameKey != null && entry.gameKey != _gameKey) continue;
      points[entry.authorId] = (points[entry.authorId] ?? 0) + entry.likes;
    }
    return points;
  }

  List<_ContributorStat> _contributorStats() {
    final names = <String, String>{};
    final likes = <String, int>{};
    final templates = <String, int>{};
    final rules = <String, int>{};

    bool keep(DateTime date) {
      if (!_monthOnly) return true;
      final now = DateTime.now();
      return date.year == now.year && date.month == now.month;
    }

    for (final entry in _templates) {
      if (!keep(entry.createdAt)) continue;
      if (_gameKey != null && entry.gameKey != _gameKey) continue;
      names[entry.authorId] = entry.authorName;
      likes[entry.authorId] = (likes[entry.authorId] ?? 0) + entry.likes;
      templates[entry.authorId] = (templates[entry.authorId] ?? 0) + 1;
    }
    for (final entry in _rules) {
      if (!keep(entry.createdAt)) continue;
      if (_gameKey != null && entry.gameKey != _gameKey) continue;
      names[entry.authorId] = entry.authorName;
      likes[entry.authorId] = (likes[entry.authorId] ?? 0) + entry.likes;
      rules[entry.authorId] = (rules[entry.authorId] ?? 0) + 1;
    }

    final me = ProfileCacheService.instance.profile;
    final ids = likes.keys.toList()
      ..sort((a, b) => (likes[b] ?? 0).compareTo(likes[a] ?? 0));
    return [
      for (final id in ids)
        _ContributorStat(
          id: id,
          name: id == me?.id ? me!.username : (names[id] ?? 'Anonyme'),
          likes: likes[id] ?? 0,
          templates: templates[id] ?? 0,
          rules: rules[id] ?? 0,
        ),
    ];
  }

  static String _rankBadge(int likes) {
    if (likes >= 50) return 'Créateur Or';
    if (likes >= 15) return 'Créateur Argent';
    if (likes >= 1) return 'Créateur Bronze';
    return 'Nouveau';
  }

  static String _ruleExcerpt(String body) {
    final sections = RuleBodyCodec.decode(body);
    if (sections.isEmpty) return body.trim();
    final buf = StringBuffer();
    for (final s in sections.take(2)) {
      final t = s.plainText.trim();
      if (t.isEmpty) continue;
      if (buf.isNotEmpty) buf.write(' · ');
      buf.write(t);
    }
    final out = buf.toString();
    if (out.length <= 140) return out;
    return '${out.substring(0, 137)}…';
  }

  Future<void> _share() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final catsCtrl = TextEditingController(text: 'Tour 1, Tour 2, Tour 3');
    var asRule = _kind == ForumKind.rules;
    final presets = NamedScorePreset.listFrom(widget.item?.metadata);
    final key = _gameKey ??
        widget.gameKey ??
        (widget.item == null
            ? null
            : CommunityRulesService.gameKeyFor(
                bggId: widget.item!.metadata?['bgg_id']?.toString(),
                title: widget.item!.title,
              ));

    String? selectedGameKey = key;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final keys = _gameKeys;
          return AlertDialog(
            title: const Text('Partager'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Template')),
                      ButtonSegment(value: true, label: Text('Règle')),
                    ],
                    selected: {asRule},
                    onSelectionChanged: (v) =>
                        setLocal(() => asRule = v.first),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGameKey ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jeu',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choisir…'),
                      ),
                      if (widget.gameKey != null)
                        DropdownMenuItem(
                          value: widget.gameKey,
                          child: Text(widget.gameTitle ?? widget.gameKey!),
                        ),
                      for (final k in keys)
                        if (k != widget.gameKey)
                          DropdownMenuItem(
                            value: k,
                            child: Text(_gameLabel(k)),
                          ),
                    ],
                    onChanged: (v) => setLocal(() {
                      selectedGameKey =
                          (v == null || v.isEmpty) ? null : v;
                    }),
                  ),
                  if (!asRule && presets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final preset in presets)
                      ListTile(
                        dense: true,
                        title: Text(preset.name),
                        trailing: TextButton(
                          onPressed: selectedGameKey == null
                              ? null
                              : () async {
                                  await CommunityScoreTemplatesService.instance
                                      .publish(
                                    gameKey: selectedGameKey!,
                                    preset: preset,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await _load();
                                  if (!mounted) return;
                                  setState(() {
                                    _gameKey = selectedGameKey;
                                    _kind = ForumKind.templates;
                                    _mineOnly = false;
                                  });
                                },
                          child: const Text('Publier'),
                        ),
                      ),
                  ],
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Titre'),
                  ),
                  if (!asRule)
                    TextField(
                      controller: catsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Catégories (séparées par des virgules)',
                      ),
                    ),
                  TextField(
                    controller: bodyCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: asRule
                          ? 'Texte de la règle'
                          : 'Conditions (texte libre)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty || selectedGameKey == null) return;
                  if (asRule) {
                    await CommunityRulesService.instance.publish(
                      gameKey: selectedGameKey!,
                      language: 'fr',
                      title: title,
                      body: bodyCtrl.text.trim(),
                    );
                  } else {
                    final lines = [
                      for (final part in catsCtrl.text.split(','))
                        if (part.trim().isNotEmpty)
                          ScoreLineSpec(part.trim()),
                    ];
                    await CommunityScoreTemplatesService.instance.publish(
                      gameKey: selectedGameKey!,
                      preset: NamedScorePreset(
                        name: title,
                        confrontation:
                            BoardgameConfrontationType.freeForAll,
                        template: BoardgameScoreTemplate(lines: lines),
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                  if (!mounted) return;
                  setState(() {
                    _gameKey = selectedGameKey;
                    _kind =
                        asRule ? ForumKind.rules : ForumKind.templates;
                    _mineOnly = false;
                    _sort = 'recent';
                  });
                },
                child: const Text('Publier'),
              ),
            ],
          );
        },
      ),
    );
    titleCtrl.dispose();
    bodyCtrl.dispose();
    catsCtrl.dispose();
  }

  Future<void> _importTemplate(CommunityScoreTemplate entry) async {
    final renamed = NamedScorePreset(
      name: '${entry.preset.name} de ${entry.authorName}',
      confrontation: entry.preset.confrontation,
      template: entry.preset.template,
      sourceAuthor: entry.authorName,
      imported: true,
    );
    if (widget.onImportTemplate != null) {
      widget.onImportTemplate!(renamed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importé : ${renamed.name}')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ouvre le Forum depuis la fiche d\'un jeu pour importer ce template.',
        ),
      ),
    );
  }

  void _openTemplate(CommunityScoreTemplate entry) {
    final isAuthor = entry.authorId == _meId || entry.authorId == 'local';
    showModalBottomSheet<void>(
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
                  entry.preset.name,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(_gameLabel(entry.gameKey)),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openContributor(entry.authorId, entry.authorName);
                  },
                  child: Text('@${entry.authorName}'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Aperçu grille',
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
                    for (final name in entry.preset.template.lineNames)
                      Chip(
                        avatar: const Text('🔘'),
                        label: Text(name),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Mode : ${entry.preset.confrontation.label}'),
                const SizedBox(height: 8),
                Text(
                  'Victoire : ${entry.preset.template.rulesPhrase}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _importTemplate(entry);
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Importer dans mes templates'),
                ),
                if (isAuthor) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await CommunityScoreTemplatesService.instance
                          .unpublish(entry.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
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

  void _openRule(CommunityRuleEntry entry) {
    final isAuthor = entry.authorId == _meId ||
        entry.authorId == 'anon' ||
        entry.authorId == 'local';
    final sections = RuleBodyCodec.decode(entry.body);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
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
                  entry.title,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(_gameLabel(entry.gameKey)),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openContributor(entry.authorId, entry.authorName);
                  },
                  child: Text('@${entry.authorName}'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(entry.language.toUpperCase()),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 8),
                if (sections.isEmpty)
                  Text(entry.body)
                else
                  ModularRuleBodyView(sections: sections),
                if (isAuthor) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await CommunityRulesService.instance
                          .unpublish(entry.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
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

  void _openContributor(String authorId, String authorName) {
    final templates = [
      for (final e in _templates)
        if (e.authorId == authorId) e,
    ]..sort((a, b) => b.likes.compareTo(a.likes));
    final rules = [
      for (final e in _rules)
        if (e.authorId == authorId) e,
    ]..sort((a, b) => b.likes.compareTo(a.likes));
    final likes = _authorPoints(forMonth: false)[authorId] ?? 0;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (ctx, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text(
                  '@$authorName',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  '${_rankBadge(likes)} · $likes likes · ${templates.length} templates · ${rules.length} règles',
                ),
                const SizedBox(height: 12),
                Text(
                  'Templates',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (templates.isEmpty)
                  const Text('Aucun template.')
                else
                  for (final e in templates)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.preset.name),
                      subtitle: Text('${e.likes} likes · ${_gameLabel(e.gameKey)}'),
                      trailing: IconButton(
                        tooltip: 'Liker',
                        onPressed: () async {
                          await CommunityScoreTemplatesService.instance
                              .toggleLike(e.id);
                          await _load();
                          if (ctx.mounted) Navigator.pop(ctx);
                          _openContributor(authorId, authorName);
                        },
                        icon: const Icon(Icons.favorite_border),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openTemplate(e);
                      },
                    ),
                const SizedBox(height: 8),
                Text(
                  'Règles',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (rules.isEmpty)
                  const Text('Aucune règle.')
                else
                  for (final e in rules)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.title),
                      subtitle: Text('${e.likes} likes · ${_gameLabel(e.gameKey)}'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openRule(e);
                      },
                    ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ContributorStat {
  final String id;
  final String name;
  final int likes;
  final int templates;
  final int rules;

  const _ContributorStat({
    required this.id,
    required this.name,
    required this.likes,
    required this.templates,
    required this.rules,
  });
}

class _ForumTabs extends StatelessWidget {
  final ForumKind kind;
  final ValueChanged<ForumKind> onChanged;

  const _ForumTabs({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(ForumKind value, String label) {
      final selected = kind == value;
      return Expanded(
        child: Material(
          color: selected
              ? scheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => onChanged(value),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab(ForumKind.templates, '📐 Templates'),
          tab(ForumKind.rules, '📖 Règles'),
          tab(ForumKind.contributors, '🏆 Contributeurs'),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> gameKeys;
  final String? gameKey;
  final String Function(String) gameLabelOf;
  final String sort;
  final bool mineOnly;
  final bool monthOnly;
  final bool showSort;
  final bool showMonth;
  final String search;
  final ValueChanged<String> onSearch;
  final void Function(String? key, String? title) onGameKey;
  final ValueChanged<String> onSort;
  final ValueChanged<bool> onMineOnly;
  final ValueChanged<bool> onMonthOnly;

  const _FilterBar({
    required this.gameKeys,
    required this.gameKey,
    required this.gameLabelOf,
    required this.sort,
    required this.mineOnly,
    required this.monthOnly,
    required this.showSort,
    required this.showMonth,
    required this.search,
    required this.onSearch,
    required this.onGameKey,
    required this.onSort,
    required this.onMineOnly,
    required this.onMonthOnly,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 40,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher…',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: onSearch,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: gameKey ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Tous les jeux', overflow: TextOverflow.ellipsis),
                  ),
                  for (final key in gameKeys)
                    DropdownMenuItem(
                      value: key,
                      child: Text(
                        gameLabelOf(key),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v == null || v.isEmpty) {
                    onGameKey(null, null);
                  } else {
                    onGameKey(v, gameLabelOf(v));
                  }
                },
              ),
            ),
          ],
        ),
        if (showSort) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _SortChip(
                  label: '🔥 Plus likés',
                  selected: sort == 'likes' && !mineOnly,
                  onTap: () {
                    onMineOnly(false);
                    onSort('likes');
                  },
                ),
                _SortChip(
                  label: '🕒 Plus récents',
                  selected: sort == 'recent' && !mineOnly,
                  onTap: () {
                    onMineOnly(false);
                    onSort('recent');
                  },
                ),
                _SortChip(
                  label: '⭐ Top créateurs',
                  selected: sort == 'author' && !mineOnly,
                  onTap: () {
                    onMineOnly(false);
                    onSort('author');
                  },
                ),
                _SortChip(
                  label: '👤 Mes partages',
                  selected: mineOnly,
                  onTap: () => onMineOnly(!mineOnly),
                ),
              ],
            ),
          ),
        ],
        if (showMonth) ...[
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Toujours')),
              ButtonSegment(value: true, label: Text('Ce mois-ci')),
            ],
            selected: {monthOnly},
            onSelectionChanged: (v) => onMonthOnly(v.first),
          ),
        ],
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _BentoGrid extends StatelessWidget {
  final List<Widget> children;

  const _BentoGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 1100 ? 3 : (w >= 720 ? 2 : 1);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 1 ? 1.55 : 1.25,
          ),
          itemCount: children.length,
          itemBuilder: (_, i) => children[i],
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final CommunityScoreTemplate entry;
  final String gameLabel;
  final Widget thumb;
  final String badge;
  final bool liked;
  final VoidCallback onAuthor;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onImport;

  const _TemplateCard({
    required this.entry,
    required this.gameLabel,
    required this.thumb,
    required this.badge,
    required this.liked,
    required this.onAuthor,
    required this.onOpen,
    required this.onLike,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  thumb,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gameLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          entry.preset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onAuthor,
                child: Text(
                  '@${entry.authorName} · $badge',
                  style: TextStyle(color: scheme.primary, fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      entry.preset.confrontation.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  for (final name in entry.preset.template.lineNames.take(4))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Text('🔘', style: TextStyle(fontSize: 10)),
                      label: Text(name, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  entry.preset.template.rulesPhrase,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Liker',
                    onPressed: onLike,
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: liked ? Colors.redAccent : null,
                    ),
                  ),
                  Text('${entry.likes}'),
                  const Spacer(),
                  TextButton(
                    onPressed: onOpen,
                    child: const Text('👁 Aperçu'),
                  ),
                  TextButton(
                    onPressed: onImport,
                    child: const Text('+ Importer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final CommunityRuleEntry entry;
  final String gameLabel;
  final Widget thumb;
  final String badge;
  final bool liked;
  final String excerpt;
  final VoidCallback onAuthor;
  final VoidCallback onOpen;
  final VoidCallback onLike;

  const _RuleCard({
    required this.entry,
    required this.gameLabel,
    required this.thumb,
    required this.badge,
    required this.liked,
    required this.excerpt,
    required this.onAuthor,
    required this.onOpen,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  thumb,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gameLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onAuthor,
                child: Text(
                  '@${entry.authorName} · $badge',
                  style: TextStyle(color: scheme.primary, fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      entry.language.toUpperCase(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Règle', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Liker',
                    onPressed: onLike,
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: liked ? Colors.redAccent : null,
                    ),
                  ),
                  Text('${entry.likes}'),
                  const Spacer(),
                  TextButton(
                    onPressed: onOpen,
                    child: const Text('👁 Aperçu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PodiumTile extends StatelessWidget {
  final int place;
  final String name;
  final int likes;
  final String badge;
  final VoidCallback onTap;

  const _PodiumTile({
    required this.place,
    required this.name,
    required this.likes,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final medal = switch (place) {
      1 => '🥇',
      2 => '🥈',
      _ => '🥉',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Text(medal, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text('$likes likes', style: const TextStyle(fontSize: 11)),
                Text(badge, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
