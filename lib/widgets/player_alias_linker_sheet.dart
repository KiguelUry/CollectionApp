import 'package:flutter/material.dart';

import '../services/global_play_history_service.dart';
import '../services/player_alias_service.dart';

Future<void> showPlayerAliasLinkerSheet(
  BuildContext context, {
  required List<String> knownNames,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PlayerAliasLinkerSheet(knownNames: knownNames),
  );
}

/// Avertissement « pseudos quasi identiques » avec action de fusion.
class AliasCollisionWarning extends StatelessWidget {
  final List<String> names;
  final VoidCallback onMerge;
  final bool enabled;

  const AliasCollisionWarning({
    super.key,
    required this.names,
    required this.onMerge,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade800;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Doublon probable : ${names.map((n) => '« $n »').join(' · ')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: enabled ? onMerge : null,
            child: const Text('Fusionner'),
          ),
        ],
      ),
    );
  }
}

class _PlayerAliasLinkerSheet extends StatefulWidget {
  final List<String> knownNames;

  const _PlayerAliasLinkerSheet({required this.knownNames});

  @override
  State<_PlayerAliasLinkerSheet> createState() =>
      _PlayerAliasLinkerSheetState();
}

class _PlayerAliasLinkerSheetState extends State<_PlayerAliasLinkerSheet> {
  final _selected = <String>{};
  final _displayController = TextEditingController();
  bool _markAsMe = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    PlayerAliasService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  void _toggle(String name, bool? selected) {
    setState(() {
      if (selected == true) {
        _selected.add(name);
        if (_displayController.text.trim().isEmpty) {
          _displayController.text = name;
        }
      } else {
        _selected.remove(name);
        if (_displayController.text.trim().toLowerCase() ==
            name.toLowerCase()) {
          _displayController.text =
              _selected.isEmpty ? '' : _selected.first;
        }
      }
    });
  }

  List<List<String>> get _collisions => findAliasCollisions(
        widget.knownNames,
        identityIdOf: (n) => PlayerAliasService.instance.identityFor(n)?.id,
      ).where((g) => !_mergedCollisionKeys.contains(aliasCollisionKey(g.first)))
          .toList();

  final _mergedCollisionKeys = <String>{};

  Future<void> _mergeCollision(List<String> names) async {
    final existing = names
        .map(PlayerAliasService.instance.identityFor)
        .whereType<PlayerIdentity>()
        .firstOrNull;
    final display = existing?.displayName ?? names.first;
    setState(() => _saving = true);
    try {
      final identity = await PlayerAliasService.instance.linkNames(
        names,
        displayName: display,
        isMe: existing?.isMe ?? false,
      );
      await GlobalPlayHistoryService().renamePlayerAcrossHistory(
        fromNames: identity.names,
        toName: identity.displayName,
      );
      if (!mounted) return;
      setState(() => _mergedCollisionKeys.add(aliasCollisionKey(names.first)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pseudos fusionnés sous « $display »')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;
    final display = _displayController.text.trim().isEmpty
        ? _selected.first
        : _displayController.text.trim();
    setState(() => _saving = true);
    try {
      final identity = await PlayerAliasService.instance.linkNames(
        _selected.toList(),
        displayName: display,
        isMe: _markAsMe,
      );

      final renamed =
          await GlobalPlayHistoryService().renamePlayerAcrossHistory(
        fromNames: identity.names,
        toName: identity.displayName,
      );

      if (!mounted) return;
      setState(() {
        _selected.clear();
        _displayController.clear();
        _markAsMe = false;
      });
      final msg = renamed > 0
          ? 'Identité enregistrée · $renamed partie${renamed > 1 ? 's' : ''} mises à jour'
          : 'Identité enregistrée';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final identities = PlayerAliasService.instance.identities;
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Identités joueurs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Regroupe les pseudos d’une même personne pour les classements. '
                'Tu peux aussi choisir un nom unique appliqué partout dans l’historique.\n'
                'Attention : si deux personnes ont écrit exactement le même pseudo '
                '(ex. « Lou »), on ne peut pas les distinguer.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              for (final group in _collisions.take(3))
                AliasCollisionWarning(
                  names: group,
                  enabled: !_saving,
                  onMerge: () => _mergeCollision(group),
                ),
              if (identities.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Identités enregistrées',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                for (final g in identities)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        g.isMe ? '${g.displayName} · moi' : g.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(g.names.join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!g.isMe)
                            IconButton(
                              tooltip: 'C’est moi',
                              icon: const Icon(Icons.person_outline, size: 20),
                              onPressed: () async {
                                await PlayerAliasService.instance.setMe(g.id);
                                if (mounted) setState(() {});
                              },
                            ),
                          IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.link_off, size: 20),
                            onPressed: () async {
                              await PlayerAliasService.instance
                                  .deleteGroup(g.id);
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Sélectionne les pseudos à regrouper',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: widget.knownNames.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun pseudo trouvé dans l’historique.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.knownNames.length,
                        itemBuilder: (context, i) {
                          final name = widget.knownNames[i];
                          final id =
                              PlayerAliasService.instance.identityFor(name);
                          final selected = _selected.contains(name);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            title: Text(name),
                            subtitle: id != null
                                ? Text(
                                    '→ ${id.displayName}${id.isMe ? ' (moi)' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  )
                                : null,
                            onChanged: (v) => _toggle(name, v),
                          );
                        },
                      ),
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _displayController,
                  decoration: const InputDecoration(
                    labelText: 'Nom affiché (appliqué partout)',
                    hintText: 'Ex. Kiki',
                    helperText:
                        'Ce nom remplace les pseudos liés dans toutes les parties.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('C’est moi'),
                  subtitle: const Text('Marque cette identité comme la tienne'),
                  value: _markAsMe,
                  onChanged: (v) => setState(() => _markAsMe = v),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving || _selected.isEmpty ? null : _confirm,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_outlined),
                label: Text(
                  _selected.isEmpty
                      ? 'Choisis au moins un pseudo'
                      : 'Enregistrer l’identité',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
