import 'package:flutter/material.dart';

import '../models/friend_choice.dart';
import '../services/friend_service.dart';
import '../services/global_play_history_service.dart';
import '../services/player_alias_service.dart';
import 'profile_avatar.dart';

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
      for (final r in rows) FriendChoice.fromFriendRow(r),
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
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Doublon : ${names.map((n) => '« $n »').join(' · ')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
        gender: existing?.gender ?? PlayerGender.masculine,
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

  Future<void> _deleteIdentity(PlayerIdentity identity) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'identité ?'),
        content: Text('« ${identity.displayName} » sera retirée.'),
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
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await PlayerAliasService.instance.deleteGroup(identity.id);
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
    final selected = <String>{
      for (final name in existing?.names ?? const <String>[]) name,
    };
    FriendChoice? friend;
    for (final choice in _friends) {
      if (choice.profileId == existing?.friendProfileId) friend = choice;
    }
    var isMe = existing?.isMe ?? false;
    var aliasQuery = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final usedElsewhere = <String>{};
          for (final identity in PlayerAliasService.instance.identities) {
            if (existing != null && identity.id == existing.id) continue;
            for (final n in identity.names) {
              usedElsewhere.add(n.toLowerCase());
            }
          }
          final aliases = <String>{
            ...widget.knownNames,
            ...?existing?.names,
          }
              .where((n) {
                final key = n.toLowerCase();
                if (selected.any((s) => s.toLowerCase() == key)) return true;
                return !usedElsewhere.contains(key);
              })
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final q = aliasQuery.trim().toLowerCase();
          final filtered = q.isEmpty
              ? aliases
              : aliases.where((n) => n.toLowerCase().contains(q)).toList();
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(
              existing == null ? 'Nouvelle identité' : 'Modifier l\'identité',
            ),
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
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pseudos de l\'historique',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Filtrer…',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => aliasQuery = v),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Aucun pseudo disponible.',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              physics: const AlwaysScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: 40,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final name = filtered[i];
                                final isOn = selected.any(
                                  (s) =>
                                      s.toLowerCase() == name.toLowerCase(),
                                );
                                return FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: ProfileAvatar(
                                    fallbackInitial: name,
                                    radius: 10,
                                  ),
                                  label: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  selected: isOn,
                                  onSelected: (on) => setLocal(() {
                                    selected.removeWhere(
                                      (s) =>
                                          s.toLowerCase() ==
                                          name.toLowerCase(),
                                    );
                                    if (on) selected.add(name);
                                    if (nameCtrl.text.trim().isEmpty &&
                                        selected.isNotEmpty) {
                                      nameCtrl.text = selected.first;
                                    }
                                  }),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: friend?.profileId ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Ami lié',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Aucun'),
                        ),
                        for (final choice in _friends)
                          DropdownMenuItem(
                            value: choice.profileId,
                            child: Row(
                              children: [
                                ProfileAvatar(
                                  avatarUrl: choice.avatarUrl,
                                  accentColorHex: choice.accentColor,
                                  fallbackInitial: choice.username,
                                  radius: 12,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    choice.username,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
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
                        if (nameCtrl.text.trim().isEmpty &&
                            alias.isNotEmpty) {
                          nameCtrl.text = alias;
                        }
                      }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
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

    // Genre : profil ami si lié, sinon masculin (→ « Gagnant »).
    final gender = isMe
        ? (existing?.gender ?? PlayerGender.masculine)
        : (friend?.playerGender ??
            existing?.gender ??
            PlayerGender.masculine);

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
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Identités joueurs',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Nom + pseudos fusionnés + ami lié.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (identities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucune identité pour l\'instant.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: identities.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final identity = identities[index];
                  FriendChoice? linked;
                  for (final f in _friends) {
                    if (f.profileId == identity.friendProfileId) {
                      linked = f;
                      break;
                    }
                  }
                  return _CompactIdentityRow(
                    identity: identity,
                    friend: linked,
                    enabled: !_saving,
                    onEdit: () => _openEditor(existing: identity),
                    onDelete: () => _deleteIdentity(identity),
                  );
                },
              ),
            ),
          for (final group in _collisions)
            AliasCollisionWarning(
              names: group,
              enabled: !_saving,
              onMerge: () => _mergeCollision(group),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : () => _openEditor(),
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Nouvelle identité'),
          ),
        ],
      ),
    );
  }
}

class _CompactIdentityRow extends StatelessWidget {
  final PlayerIdentity identity;
  final FriendChoice? friend;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CompactIdentityRow({
    required this.identity,
    required this.friend,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = identity.names
        .where(
          (n) => n.toLowerCase() != identity.displayName.toLowerCase(),
        )
        .toList();
    final linkedName =
        (friend?.username ?? identity.friendUsername ?? '').trim();

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onEdit : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
          child: Row(
            children: [
              ProfileAvatar(
                avatarUrl: friend?.avatarUrl,
                accentColorHex: friend?.accentColor,
                fallbackInitial: identity.displayName,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      identity.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    for (final pseudo in extras.take(6))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          pseudo,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (linkedName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ProfileAvatar(
                              avatarUrl: friend?.avatarUrl,
                              accentColorHex: friend?.accentColor,
                              fallbackInitial: linkedName,
                              radius: 8,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              linkedName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (identity.isMe)
                      Text(
                        'moi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onEdit : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Supprimer',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onDelete : null,
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.red.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
