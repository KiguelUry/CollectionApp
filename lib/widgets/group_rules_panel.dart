import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/group_community_service.dart';
import 'markdown_rules_editor.dart';

/// Règles collectives d'un jeu au sein d'un groupe (wiki + votes).
class GroupRulesPanel extends StatefulWidget {
  final String groupId;
  final String itemId;
  final String itemTitle;
  final Color accent;

  const GroupRulesPanel({
    super.key,
    required this.groupId,
    required this.itemId,
    required this.itemTitle,
    required this.accent,
  });

  @override
  State<GroupRulesPanel> createState() => _GroupRulesPanelState();
}

class _GroupRulesPanelState extends State<GroupRulesPanel> {
  final _service = GroupCommunityService();
  bool _loading = true;
  bool _showAll = false;
  List<GroupRuleEntry> _rules = [];
  String? _preferredRuleId;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  String get _prefKey => 'preferred_rule_${widget.groupId}_${widget.itemId}';

  @override
  void initState() {
    super.initState();
    _loadPreferred();
    _load();
  }

  Future<void> _loadPreferred() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _preferredRuleId = prefs.getString(_prefKey));
  }

  Future<void> _setPreferred(String ruleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, ruleId);
    if (mounted) setState(() => _preferredRuleId = ruleId);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rules = await _service.fetchRules(
      groupId: widget.groupId,
      itemId: widget.itemId,
    );
    if (mounted) {
      setState(() {
        _rules = rules;
        _loading = false;
      });
    }
  }

  GroupRuleEntry? get _featuredRule {
    if (_rules.isEmpty) return null;
    if (_preferredRuleId != null) {
      for (final r in _rules) {
        if (r.id == _preferredRuleId) return r;
      }
    }
    return _rules.first;
  }

  Future<void> _addRule() async {
    final titleController = TextEditingController(text: 'Notre variante');
    final bodyController = TextEditingController();
    final ok = await _openRuleDialog(
      title: 'Ajouter une variante',
      titleController: titleController,
      bodyController: bodyController,
    );
    if (ok != true) return;
    final body = bodyController.text.trim();
    if (body.isEmpty) return;
    final created = await _service.addRule(
      groupId: widget.groupId,
      itemId: widget.itemId,
      title: titleController.text.trim(),
      body: body,
    );
    if (created != null) await _setPreferred(created.id);
    _load();
  }

  Future<void> _editRule(GroupRuleEntry rule) async {
    final titleController = TextEditingController(text: rule.title);
    final bodyController = TextEditingController(text: rule.body);
    final ok = await _openRuleDialog(
      title: 'Modifier la variante',
      titleController: titleController,
      bodyController: bodyController,
    );
    if (ok != true) return;
    final body = bodyController.text.trim();
    if (body.isEmpty) return;
    await _service.updateRule(
      ruleId: rule.id,
      title: titleController.text.trim(),
      body: body,
    );
    _load();
  }

  Future<void> _deleteRule(GroupRuleEntry rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette variante ?'),
        content: Text('« ${rule.title} » sera définitivement supprimée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteRule(rule.id);
    if (_preferredRuleId == rule.id) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      if (mounted) setState(() => _preferredRuleId = null);
    }
    _load();
  }

  Future<bool?> _openRuleDialog({
    required String title,
    required TextEditingController titleController,
    required TextEditingController bodyController,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Titre'),
                  ),
                  const SizedBox(height: 12),
                  MarkdownRulesEditor(
                    controller: bodyController,
                    hint: '## Objectif\n\n- Règle 1',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleVote(GroupRuleEntry rule) async {
    await _service.toggleVote(rule.id, !rule.votedByMe);
    _load();
  }

  Widget _ruleCard(GroupRuleEntry rule, {required bool featured}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: featured ? widget.accent.withValues(alpha: 0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (featured)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.push_pin,
                      size: 16,
                      color: widget.accent,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (rule.authorName != null)
                        Text(
                          'Par ${rule.authorName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!_showAll && _rules.length > 1)
                  TextButton(
                    onPressed: () => _setPreferred(rule.id),
                    child: Text(
                      _preferredRuleId == rule.id
                          ? 'Affichée'
                          : 'Afficher',
                    ),
                  ),
                if (rule.authorId == _userId) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Modifier',
                    onPressed: () => _editRule(rule),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Supprimer',
                    onPressed: () => _deleteRule(rule),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleVote(rule),
                  icon: Icon(
                    rule.votedByMe
                        ? Icons.thumb_up
                        : Icons.thumb_up_outlined,
                    color: widget.accent,
                    size: 20,
                  ),
                ),
                Text('${rule.voteCount}'),
              ],
            ),
            const SizedBox(height: 6),
            MarkdownBody(
              data: rule.body,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featuredRule;
    final others = featured == null
        ? <GroupRuleEntry>[]
        : _rules.where((r) => r.id != featured.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Règles du groupe',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: _addRule,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        Text(
          'Variantes pour « ${widget.itemTitle} » — une seule affichée par défaut, modifiable par chacun.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_rules.isEmpty)
          Text(
            'Aucune variante pour l\'instant. Propose la vôtre !',
            style: TextStyle(color: Colors.grey.shade600),
          )
        else ...[
          if (featured != null) _ruleCard(featured, featured: true),
          if (_rules.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showAll = !_showAll),
                icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _showAll
                      ? 'Masquer les autres variantes'
                      : 'Voir toutes les variantes (${_rules.length})',
                ),
              ),
            ),
          if (_showAll)
            for (final rule in others) _ruleCard(rule, featured: false),
        ],
      ],
    );
  }
}
