import 'package:flutter/material.dart';

import '../models/friend_choice.dart';
import '../services/friend_service.dart';
import '../services/global_play_history_service.dart';
import '../services/player_alias_service.dart';

Future<void> showPlayerAliasLinkerSheet(
  BuildContext context, {
  required List<String> knownNames,
  VoidCallback? onMutated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => PlayerAliasLinkerSheet(
      knownNames: knownNames,
      onMutated: onMutated,
    ),
  );
}

Future<List<FriendChoice>> _loadFriendChoices() async {
  try {
    final rows = await FriendService().fetchFriends();
    return [
      for (final r in rows)
        FriendChoice.fromFriendRow(r),
    ];
  } catch (_) {
    return const [];
  }
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

class PlayerAliasLinkerSheet extends StatefulWidget {
  final List<String> knownNames;

  /// Injectable pour les tests (sinon amis Supabase).
  final Future<List<FriendChoice>> Function()? loadFriends;
  final VoidCallback? onMutated;

  const PlayerAliasLinkerSheet({
    super.key,
    required this.knownNames,
    this.loadFriends,
    this.onMutated,
  });

  @override
  State<PlayerAliasLinkerSheet> createState() =>
      _PlayerAliasLinkerSheetState();
}

class _PlayerAliasLinkerSheetState extends State<PlayerAliasLinkerSheet> {
  bool _saving = false;
  List<FriendChoice> _friends = const [];

  @override
  void initState() {
    super.initState();
    PlayerAliasService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    (widget.loadFriends ?? _loadFriendChoices)().then((list) {
      if (mounted) setState(() => _friends = list);
    });
  }

  List<List<String>> get _collisions => findAliasCollisions(
        widget.knownNames,
        identityIdOf: (n) => PlayerAliasService.instance.identityFor(n)?.id,
      );

  Future<void> _mergeCollision(List<String> names) async {
    final existing = names
        .map(PlayerAliasService.instance.identityFor)
        .whereType<PlayerIdentity>()
        .firstOrNull;
    setState(() => _saving = true);
    try {
      final identity = await PlayerAliasService.instance.linkNames(
        names,
        displayName: existing?.displayName ?? names.first,
        isMe: existing?.isMe ?? false,
        gender: existing?.gender,
      );
      await GlobalPlayHistoryService().renamePlayerAcrossHistory(
        fromNames: identity.names,
        toName: identity.displayName,
      );
      widget.onMutated?.call();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEditor({PlayerIdentity? existing}) async {
    final nameCtrl = TextEditingController(
      text: existing?.displayName ?? '',
    );
    var gender = existing?.gender ?? PlayerGender.neutral;
    final selected = <String>{
      for (final name in existing?.names ?? const <String>[]) name,
    };
    FriendChoice? friend;
    for (final choice in _friends) {
      if (choice.profileId == existing?.friendProfileId) friend = choice;
    }
    var isMe = existing?.isMe ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final aliases = <String>{
            ...widget.knownNames,
            ...?existing?.names,
          }.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return AlertDialog(
            title: Text(existing == null ? 'Nouvelle identité' : 'Identité'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom principal affiché',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<PlayerGender>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: PlayerGender.feminine, label: Text('F')),
                        ButtonSegment(value: PlayerGender.masculine, label: Text('M')),
                        ButtonSegment(value: PlayerGender.neutral, label: Text('Neutre')),
                      ],
                      selected: {gender},
                      onSelectionChanged: (v) => setLocal(() => gender = v.first),
                    ),
                    const SizedBox(height: 12),
                    const Text('Pseudos de l\'historique'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in aliases)
                          FilterChip(
                            label: Text(name),
                            selected: selected.any(
                              (s) => s.toLowerCase() == name.toLowerCase(),
                            ),
                            onSelected: (on) => setLocal(() {
                              selected.removeWhere(
                                (s) => s.toLowerCase() == name.toLowerCase(),
                              );
                              if (on) selected.add(name);
                              if (nameCtrl.text.trim().isEmpty && selected.isNotEmpty) {
                                nameCtrl.text = selected.first;
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: friend?.profileId ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ami lié'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Aucun')),
                        for (final choice in _friends)
                          DropdownMenuItem(
                            value: choice.profileId,
                            child: Text(choice.username),
                          ),
                      ],
                      onChanged: (id) => setLocal(() {
                        friend = null;
                        for (final choice in _friends) {
                          if (choice.profileId == id) friend = choice;
                        }
                        final alias = friend?.username.trim() ?? '';
                        if (alias.isNotEmpty &&
                            !selected.any(
                              (s) => s.toLowerCase() == alias.toLowerCase(),
                            )) {
                          selected.add(alias);
                        }
                      }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('C\'est moi'),
                      value: isMe,
                      onChanged: (v) => setLocal(() {
                        isMe = v;
                        if (v) friend = null;
                      }),
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
      ),
    );
    final display = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (saved != true || !mounted) return;
    final names = selected.toList();
    if (display.isNotEmpty &&
        !names.any((n) => n.toLowerCase() == display.toLowerCase())) {
      names.insert(0, display);
    }
    if (names.isEmpty) return;
    setState(() => _saving = true);
    try {
      final identity = await PlayerAliasService.instance.linkNames(
        names,
        displayName: display.isEmpty ? names.first : display,
        isMe: isMe,
        gender: gender,
        friendProfileId: isMe ? null : friend?.profileId,
        friendUsername: isMe ? null : friend?.username,
      );
      await GlobalPlayHistoryService().renamePlayerAcrossHistory(
        fromNames: identity.names,
        toName: identity.displayName,
      );
      widget.onMutated?.call();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identities = PlayerAliasService.instance.identities;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Identités joueurs',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Un nom affiché, des pseudos regroupés, un ami lié.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (identities.isEmpty)
            const Text('Aucune identité pour l\'instant.')
          else
            for (final identity in identities)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(identity.displayName),
                  subtitle: Text(
                    [
                      identity.names.join(' · '),
                      if ((identity.friendUsername ?? '').isNotEmpty)
                        'Ami : ${identity.friendUsername}',
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _saving ? null : () => _openEditor(existing: identity),
                ),
              ),
          for (final group in _collisions)
            AliasCollisionWarning(
              names: group,
              enabled: !_saving,
              onMerge: () => _mergeCollision(group),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _openEditor(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Nouvelle identité'),
          ),
        ],
      ),
    );
  }
}
