import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
  List<GroupRuleEntry> _rules = [];
  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
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
    await _service.addRule(
      groupId: widget.groupId,
      itemId: widget.itemId,
      title: titleController.text.trim(),
      body: body,
    );
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

  @override
  Widget build(BuildContext context) {
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
          'Variantes pour « ${widget.itemTitle} » — la plus votée est épinglée.',
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
        else
          for (final rule in _rules)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: rule == _rules.first
                  ? widget.accent.withValues(alpha: 0.08)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (rule == _rules.first)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.push_pin,
                              size: 16,
                              color: widget.accent,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            rule.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (rule.authorId == _userId)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Modifier',
                            onPressed: () => _editRule(rule),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
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
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
