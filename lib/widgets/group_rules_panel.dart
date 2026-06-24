import 'package:flutter/material.dart';

import '../services/group_community_service.dart';

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter une variante'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(
                labelText: 'Règles / résumé',
              ),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publier'),
          ),
        ],
      ),
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
                            child: Icon(Icons.push_pin, size: 16, color: widget.accent),
                          ),
                        Expanded(
                          child: Text(
                            rule.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
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
                    Text(rule.body),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
