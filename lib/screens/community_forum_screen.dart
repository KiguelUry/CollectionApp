import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/boardgame_score_grid.dart';
import '../models/collection_item.dart';
import '../services/community_rules_service.dart';
import '../services/community_score_templates_service.dart';
import '../services/profile_cache_service.dart';

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
  bool _monthOnly = false;
  bool _mineOnly = false;
  List<CommunityScoreTemplate> _templates = [];
  List<CommunityRuleEntry> _rules = [];

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _gameKey = widget.gameKey;
    _load();
  }

  Future<void> _load() async {
    final templates = await CommunityScoreTemplatesService.instance.all();
    final rules = await CommunityRulesService.instance.all();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _rules = rules;
    });
  }

  List<String> get _gameKeys {
    final keys = <String>{
      for (final template in _templates) template.gameKey,
      for (final rule in _rules) rule.gameKey,
      if (_gameKey != null) _gameKey!,
    };
    return keys.toList()..sort();
  }

  bool _recentEnough(DateTime date) {
    if (!_monthOnly) return true;
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.gameTitle == null
              ? 'Forum communautaire'
              : 'Forum · ${widget.gameTitle}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SegmentedButton<ForumKind>(
              showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ForumKind.templates,
                label: Text('Templates'),
              ),
              ButtonSegment(value: ForumKind.rules, label: Text('Règles')),
              ButtonSegment(
                value: ForumKind.contributors,
                label: Text('Contributeurs'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _gameKey ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Jeu', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tous les jeux')),
              for (final key in _gameKeys)
                DropdownMenuItem(value: key, child: Text(_gameLabel(key))),
            ],
            onChanged: (value) => setState(() {
              _gameKey = value == null || value.isEmpty ? null : value;
            }),
          ),
          if (_kind != ForumKind.contributors) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Plus likés'),
                  selected: _sort == 'likes',
                  onSelected: (_) => setState(() => _sort = 'likes'),
                ),
                ChoiceChip(
                  label: const Text('Plus récents'),
                  selected: _sort == 'recent',
                  onSelected: (_) => setState(() => _sort = 'recent'),
                ),
                ChoiceChip(
                  label: const Text('Meilleures notes du créateur'),
                  selected: _sort == 'author',
                  onSelected: (_) => setState(() => _sort = 'author'),
                ),
                FilterChip(
                  label: const Text('Mes contributions'),
                  selected: _mineOnly,
                  onSelected: (value) => setState(() => _mineOnly = value),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<bool>(
              showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Toujours')),
                  ButtonSegment(value: true, label: Text('Du mois')),
                ],
                selected: {_monthOnly},
                onSelectionChanged: (value) =>
                    setState(() => _monthOnly = value.first),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.add),
            label: Text(
              _kind == ForumKind.rules
                  ? 'Partager une règle'
                  : 'Partager un template / une règle',
            ),
          ),
          const SizedBox(height: 16),
          if (_kind == ForumKind.templates)
            _cardGrid(_templateCards(me))
          else if (_kind == ForumKind.rules)
            _cardGrid(_ruleCards(me))
          else
            ..._contributorCards(),
        ],
      ),
    );
  }

  String _gameLabel(String key) {
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

  Widget _cardGrid(List<Widget> cards) {
    if (cards.length == 1 && cards.first is Text) return cards.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns == 2 ? 1.35 : 1.7,
          children: cards,
        );
      },
    );
  }

  Widget _thumb(String gameKey) {
    final url = widget.gameKey == gameKey ? widget.item?.imageUrl : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 42,
        height: 42,
        child: url == null || url.isEmpty
            ? const ColoredBox(
                color: Color(0xFF1A1C1F),
                child: Icon(Icons.casino_outlined, size: 20),
              )
            : Image.network(url, fit: BoxFit.cover),
      ),
    );
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
            ? 'title:général'
            : CommunityRulesService.gameKeyFor(
                bggId: widget.item!.metadata?['bgg_id']?.toString(),
                title: widget.item!.title,
              ));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
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
                  onSelectionChanged: (v) => setLocal(() => asRule = v.first),
                ),
                if (!asRule && presets.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final preset in presets)
                    ListTile(
                      dense: true,
                      title: Text(preset.name),
                      trailing: TextButton(
                        onPressed: () async {
                          await CommunityScoreTemplatesService.instance.publish(
                            gameKey: key,
                            preset: preset,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
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
                if (title.isEmpty) return;
                if (asRule) {
                  await CommunityRulesService.instance.publish(
                    gameKey: key,
                    language: 'fr',
                    title: title,
                    body: bodyCtrl.text.trim(),
                  );
                } else {
                  final lines = [
                    for (final part in catsCtrl.text.split(','))
                      if (part.trim().isNotEmpty) ScoreLineSpec(part.trim()),
                  ];
                  await CommunityScoreTemplatesService.instance.publish(
                    gameKey: key,
                    preset: NamedScorePreset(
                      name: title,
                      confrontation: BoardgameConfrontationType.freeForAll,
                      template: BoardgameScoreTemplate(lines: lines),
                    ),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    bodyCtrl.dispose();
    catsCtrl.dispose();
  }

  List<Widget> _templateCards(String? me) {
    final points = _authorPoints();
    final list = [
      for (final entry in _templates)
        if ((_gameKey == null || entry.gameKey == _gameKey) &&
            _recentEnough(entry.createdAt) &&
            (!_mineOnly || entry.authorId == me))
          entry,
    ];
    list.sort((a, b) {
      if (_sort == 'recent') return b.createdAt.compareTo(a.createdAt);
      if (_sort == 'author') {
        return (points[b.authorId] ?? 0).compareTo(points[a.authorId] ?? 0);
      }
      return b.likes.compareTo(a.likes);
    });
    if (list.isEmpty) return [const Text('Aucun template pour ce filtre.')];
    return [
      for (final entry in list)
        _ForumCard(
          gameLabel: _gameLabel(entry.gameKey),
          thumb: _thumb(entry.gameKey),
          title: entry.preset.name,
          author: entry.authorName,
          likes: entry.likes,
          chips: entry.preset.template.lineNames,
          detail: entry.preset.template.rulesPhrase,
          onOpen: () => _openTemplate(entry),
          onLike: () async {
            await CommunityScoreTemplatesService.instance.toggleLike(entry.id);
            await _load();
          },
          onImport: widget.onImportTemplate == null
              ? null
              : () => widget.onImportTemplate!(entry.preset),
        ),
    ];
  }

  void _openTemplate(CommunityScoreTemplate entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entry.preset.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_gameLabel(entry.gameKey)),
              const SizedBox(height: 8),
              Text('@${entry.authorName}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in entry.preset.template.lineNames)
                    Chip(label: Text(name)),
                ],
              ),
              const SizedBox(height: 8),
              Text(entry.preset.template.rulesPhrase),
            ],
          ),
        ),
        actions: [
          if (widget.onImportTemplate != null)
            TextButton(
              onPressed: () {
                widget.onImportTemplate!(entry.preset);
                Navigator.pop(ctx);
              },
              child: const Text('Importer'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  List<Widget> _ruleCards(String? me) {
    final points = _authorPoints();
    final list = [
      for (final entry in _rules)
        if ((_gameKey == null || entry.gameKey == _gameKey) &&
            _recentEnough(entry.createdAt) &&
            (!_mineOnly || entry.authorId == me))
          entry,
    ];
    list.sort((a, b) {
      if (_sort == 'recent') return b.createdAt.compareTo(a.createdAt);
      if (_sort == 'author') {
        return (points[b.authorId] ?? 0).compareTo(points[a.authorId] ?? 0);
      }
      return b.likes.compareTo(a.likes);
    });
    if (list.isEmpty) return [const Text('Aucune règle pour ce filtre.')];
    return [
      for (final entry in list)
        _ForumCard(
          gameLabel: _gameLabel(entry.gameKey),
          thumb: _thumb(entry.gameKey),
          title: entry.title,
          author: entry.authorName,
          likes: entry.likes,
          chips: const [],
          detail: entry.body,
          onOpen: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(entry.title),
                content: Text(entry.body),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            );
          },
          onLike: () async {
            await CommunityRulesService.instance.toggleLike(entry.id);
            await _load();
          },
        ),
    ];
  }

  Map<String, int> _authorPoints() {
    final points = <String, int>{};
    for (final entry in _templates) {
      if (!_recentEnough(entry.createdAt)) continue;
      points[entry.authorId] = (points[entry.authorId] ?? 0) + entry.likes;
    }
    for (final entry in _rules) {
      if (!_recentEnough(entry.createdAt)) continue;
      points[entry.authorId] = (points[entry.authorId] ?? 0) + entry.likes;
    }
    return points;
  }

  List<Widget> _contributorCards() {
    final names = <String, String>{};
    for (final entry in _templates) {
      names[entry.authorId] = entry.authorName;
    }
    for (final entry in _rules) {
      names[entry.authorId] = entry.authorName;
    }
    final points = _authorPoints();
    final ids = points.keys.toList()
      ..sort((a, b) => (points[b] ?? 0).compareTo(points[a] ?? 0));
    if (ids.isEmpty) return [const Text('Aucun contributeur pour l\'instant.')];
    final me = ProfileCacheService.instance.profile;
    return [
      for (final id in ids)
        ListTile(
          leading: CircleAvatar(
            child: Text((names[id] ?? '?').characters.first.toUpperCase()),
          ),
          title: Text(id == me?.id ? me!.username : (names[id] ?? 'Anonyme')),
          subtitle: Text('${points[id]} like${(points[id] ?? 0) > 1 ? 's' : ''}'),
          onTap: () {
            setState(() {
              _mineOnly = id == me?.id;
              _kind = ForumKind.templates;
            });
          },
        ),
    ];
  }
}

class _ForumCard extends StatelessWidget {
  final String gameLabel;
  final Widget thumb;
  final String title;
  final String author;
  final int likes;
  final List<String> chips;
  final String detail;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback? onImport;

  const _ForumCard({
    required this.gameLabel,
    required this.thumb,
    required this.title,
    required this.author,
    required this.likes,
    required this.chips,
    required this.detail,
    required this.onOpen,
    required this.onLike,
    this.onImport,
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
                    child: Text(
                      gameLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              GestureDetector(
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('@$author'),
                      content: Text('$likes like${likes > 1 ? 's' : ''}'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Fermer'),
                        ),
                      ],
                    ),
                  );
                },
                child: Text(
                  '@$author · $likes like${likes > 1 ? 's' : ''}',
                  style: TextStyle(color: scheme.primary, fontSize: 12),
                ),
              ),
              if (chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final chip in chips.take(4))
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(chip, style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Liker',
                    onPressed: onLike,
                    icon: const Icon(Icons.favorite_border, size: 18),
                  ),
                  if (onImport != null)
                    TextButton(onPressed: onImport, child: const Text('Importer')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
