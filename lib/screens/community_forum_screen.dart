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
                DropdownMenuItem(value: key, child: Text(key)),
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
                segments: const [
                  ButtonSegment(value: false, label: Text('Toujours')),
                  ButtonSegment(value: true, label: Text('Du mois')),
                ],
                selected: {_monthOnly},
                onSelectionChanged: (value) =>
                    setState(() => _monthOnly = value.first),
              ),
            ),
          const SizedBox(height: 16),
          if (_kind == ForumKind.templates)
            ..._templateCards(me)
          else if (_kind == ForumKind.rules)
            ..._ruleCards(me)
          else
            ..._contributorCards(),
        ],
      ),
    );
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
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(entry.preset.name),
            subtitle: Text(
              '${entry.authorName} · ${entry.likes} like${entry.likes > 1 ? 's' : ''}\n'
              '${entry.preset.template.lineNames.join(' · ')}\n'
              '${entry.preset.template.rules.length} condition(s)',
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Liker',
                  onPressed: () async {
                    await CommunityScoreTemplatesService.instance
                        .toggleLike(entry.id);
                    await _load();
                  },
                  icon: const Icon(Icons.favorite_border),
                ),
                TextButton(
                  onPressed: widget.onImportTemplate == null
                      ? null
                      : () => widget.onImportTemplate!(entry.preset),
                  child: const Text('Importer'),
                ),
              ],
            ),
          ),
        ),
    ];
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
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(entry.title),
            subtitle: Text(
              '${entry.authorName} · ${entry.likes} like${entry.likes > 1 ? 's' : ''}\n${entry.body}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Liker',
              onPressed: () async {
                await CommunityRulesService.instance.toggleLike(entry.id);
                await _load();
              },
              icon: const Icon(Icons.favorite_border),
            ),
          ),
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
