import 'package:flutter/material.dart';

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

class _PlayerAliasLinkerSheet extends StatefulWidget {
  final List<String> knownNames;

  const _PlayerAliasLinkerSheet({required this.knownNames});

  @override
  State<_PlayerAliasLinkerSheet> createState() =>
      _PlayerAliasLinkerSheetState();
}

class _PlayerAliasLinkerSheetState extends State<_PlayerAliasLinkerSheet> {
  final _selected = <String>{};
  String? _anchor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    PlayerAliasService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _confirmLink() async {
    if (_selected.length < 2) return;
    setState(() => _saving = true);
    try {
      await PlayerAliasService.instance.linkNames(_selected.toList());
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _anchor = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Noms liés — même personne')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = PlayerAliasService.instance.groups;
    final height = MediaQuery.sizeOf(context).height * 0.78;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lier des noms',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pour lier plusieurs noms de la même personne (ex. Kiki, Kig, Goran). '
                'Les noms restent dans l\'historique, mais on sait que c\'est le même joueur.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Groupes existants',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                for (final g in groups)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(g.names.join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Supprimer le lien',
                      icon: const Icon(Icons.link_off, size: 20),
                      onPressed: () async {
                        await PlayerAliasService.instance.deleteGroup(g.id);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                _anchor == null
                    ? 'Choisis un premier nom'
                    : 'Lier « $_anchor » avec…',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: widget.knownNames.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun joueur trouvé dans l\'historique.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.knownNames.length,
                        itemBuilder: (context, i) {
                          final name = widget.knownNames[i];
                          final aliases =
                              PlayerAliasService.instance.aliasesFor(name);
                          final selected = _selected.contains(name);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            title: Text(name),
                            subtitle: aliases.length > 1
                                ? Text(
                                    'Déjà lié : ${aliases.join(' · ')}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  )
                                : null,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selected.add(name);
                                  _anchor ??= name;
                                } else {
                                  _selected.remove(name);
                                  if (_anchor == name) {
                                    _anchor = _selected.isEmpty
                                        ? null
                                        : _selected.first;
                                  }
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving || _selected.length < 2
                    ? null
                    : _confirmLink,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  _selected.length < 2
                      ? 'Sélectionne au moins 2 noms'
                      : 'C\'est la même personne (${_selected.length})',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
