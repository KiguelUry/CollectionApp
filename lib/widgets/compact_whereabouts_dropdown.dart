import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/holder_place_history_service.dart';
import '../services/household_service.dart';
import '../services/social_directory_cache.dart';
import '../utils/holder_label_utils.dart';
import 'households_sheet.dart';
import 'profile_avatar.dart';

/// « Chez qui ? » — puces rapides (personnes + foyers/lieux).
class CompactWhereaboutsDropdown extends StatefulWidget {
  final List<CollectionGroup> groups;
  final Set<String> selectedGroupIds;
  final String? locationUserId;
  final String? holderLabel;
  final bool readOnly;
  final bool applyDefaultIfEmpty;
  final void Function({
    String? locationUserId,
    String? holderLabel,
    bool clearHolder,
    bool manualHolder,
  }) onChanged;

  const CompactWhereaboutsDropdown({
    super.key,
    required this.groups,
    required this.selectedGroupIds,
    required this.locationUserId,
    required this.holderLabel,
    required this.readOnly,
    this.applyDefaultIfEmpty = false,
    required this.onChanged,
  });

  @override
  State<CompactWhereaboutsDropdown> createState() =>
      _CompactWhereaboutsDropdownState();
}

class _MemberOption {
  final String userId;
  final String label;
  final String? avatarUrl;
  final String? accentColor;

  const _MemberOption({
    required this.userId,
    required this.label,
    this.avatarUrl,
    this.accentColor,
  });
}

enum _WhoPane { person, place }

class _CompactWhereaboutsDropdownState
    extends State<CompactWhereaboutsDropdown> {
  final _groupService = GroupService();
  final _friendService = FriendService();
  final _manualFocusNode = FocusNode();
  late TextEditingController _manualController;

  String? _meUserId;
  List<_MemberOption> _people = [];
  List<Household> _homes = [];
  List<String> _placeSuggestions = [];
  bool _defaultApplied = false;
  bool _manualMode = false;
  _WhoPane? _pane;

  bool get _manualIsPlace => _pane != _WhoPane.person;

  String? get _personalUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _manualController = TextEditingController(
      text: widget.holderLabel == null
          ? ''
          : holderLabelStorageValue(widget.holderLabel!),
    );
    _meUserId = _personalUserId;
    _seedFromCache();
    unawaited(_loadRemote());
  }

  void _seedFromCache() {
    final cache = SocialDirectoryCache.instance;
    if (!cache.ready && HouseholdService.instance.homes.isEmpty) return;
    final people = <String, _MemberOption>{};
    for (final f in cache.friends) {
      final id = f['profile_id']?.toString();
      if (id == null || id == _meUserId) continue;
      people[id] = _MemberOption(
        userId: id,
        label: f['username']?.toString() ?? 'Ami',
        avatarUrl: f['avatar_url']?.toString(),
        accentColor: f['accent_color']?.toString(),
      );
    }
    _people = people.values.toList()..sort((a, b) => a.label.compareTo(b.label));
    _homes = [...HouseholdService.instance.homes];
    _placeSuggestions = [...cache.places];
  }

  @override
  void dispose() {
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRemote() async {
    if (!SocialDirectoryCache.instance.ready) {
      await SocialDirectoryCache.instance.warm();
    }
    await HouseholdService.instance.ensureLoaded();
    final people = <String, _MemberOption>{};
    try {
      for (final g in widget.groups) {
        final members = await _groupService.fetchMembers(g.id);
        for (final m in members) {
          final id = m['profile_id']?.toString();
          if (id == null || id == _meUserId) continue;
          final profile = m['profiles'] ?? m['profile'];
          final map = profile is Map ? Map<String, dynamic>.from(profile) : m;
          final label = map['username']?.toString() ?? 'Membre';
          people[id] = _MemberOption(
            userId: id,
            label: label,
            avatarUrl: map['avatar_url']?.toString(),
            accentColor: map['accent_color']?.toString(),
          );
        }
      }
      final friends = await _friendService.fetchFriends();
      for (final f in friends) {
        final id = f['profile_id']?.toString();
        if (id == null || id == _meUserId) continue;
        people.putIfAbsent(
          id,
          () => _MemberOption(
            userId: id,
            label: f['username']?.toString() ?? 'Ami',
            avatarUrl: f['avatar_url']?.toString(),
            accentColor: f['accent_color']?.toString(),
          ),
        );
      }
    } catch (_) {}
    await _loadPlaceSuggestions();
    if (!mounted) return;
    setState(() {
      _people = people.values.toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      _homes = [...HouseholdService.instance.homes];
    });
    _maybeApplyDefault();
  }

  Future<void> _loadPlaceSuggestions() async {
    final places = await HolderPlaceHistoryService.loadForGroups(
      widget.selectedGroupIds,
      personalUserId: widget.selectedGroupIds.isEmpty ? _personalUserId : null,
    );
    if (!mounted) return;
    setState(() {
      _placeSuggestions = {
        ...places,
        ...SocialDirectoryCache.instance.places,
      }.toList();
    });
  }

  void _maybeApplyDefault() {
    if (_defaultApplied || !widget.applyDefaultIfEmpty || widget.readOnly) {
      return;
    }
    if (widget.locationUserId != null ||
        (widget.holderLabel != null && widget.holderLabel!.trim().isNotEmpty)) {
      return;
    }
    if (_meUserId == null) return;
    _defaultApplied = true;
    widget.onChanged(locationUserId: _meUserId, holderLabel: 'Chez moi');
  }

  bool _isSelectedUser(String userId) =>
      !_manualMode && widget.locationUserId == userId;

  bool _isHomeSelected(Household home) {
    final label = widget.holderLabel ?? '';
    if (label.isEmpty) return false;
    final bare = holderLabelStorageValue(label).trim().toLowerCase();
    return bare == home.place.trim().toLowerCase() ||
        home.people.any((p) => p.trim().toLowerCase() == bare);
  }

  void _selectUser(String userId, String label) {
    if (widget.readOnly) return;
    setState(() => _manualMode = false);
    widget.onChanged(locationUserId: userId, holderLabel: label);
  }

  void _selectHome(Household home) {
    if (widget.readOnly) return;
    setState(() => _manualMode = false);
    widget.onChanged(
      holderLabel: home.placeLabel,
      manualHolder: true,
      clearHolder: false,
    );
  }

  void _applySuggestion(String raw) {
    _manualController.text = raw;
    _submitManual(skipConfirm: true);
  }

  Future<void> _submitManual({bool skipConfirm = false}) async {
    final t = _manualController.text.trim();
    if (t.isEmpty) return;

    final preview = formatManualHolderLabel(
      t,
      kind: _manualIsPlace ? ManualHolderKind.place : ManualHolderKind.person,
    );
    if (!skipConfirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmer le lieu'),
          content: Text(
            'Afficher comme :\n\n$preview',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Modifier'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    _manualFocusNode.unfocus();
    setState(() => _manualMode = true);
    await HolderPlaceHistoryService.saveForGroups(
      widget.selectedGroupIds,
      preview,
      personalUserId: widget.selectedGroupIds.isEmpty ? _personalUserId : null,
    );
    await _loadPlaceSuggestions();
    if (!mounted) return;
    widget.onChanged(holderLabel: preview, manualHolder: true);
  }

  Future<void> _removeSuggestion(String place) async {
    await HolderPlaceHistoryService.removeForGroups(
      widget.selectedGroupIds,
      place,
      personalUserId: widget.selectedGroupIds.isEmpty ? _personalUserId : null,
    );
    await _loadPlaceSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Chez qui ?',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_meUserId != null)
              FilterChip(
                avatar: const Icon(Icons.home_outlined, size: 16),
                label: const Text('Chez moi'),
                selected: _isSelectedUser(_meUserId!),
                onSelected: widget.readOnly
                    ? null
                    : (_) {
                        setState(() => _pane = null);
                        _selectUser(_meUserId!, 'Chez moi');
                      },
              ),
            FilterChip(
              avatar: const Icon(Icons.person_outline, size: 16),
              label: const Text('Personne'),
              selected: _pane == _WhoPane.person,
              onSelected: widget.readOnly
                  ? null
                  : (_) => setState(() {
                        _pane = _pane == _WhoPane.person ? null : _WhoPane.person;
                        _manualMode = _pane == _WhoPane.person;
                      }),
            ),
            FilterChip(
              avatar: const Icon(Icons.place_outlined, size: 16),
              label: const Text('Lieu'),
              selected: _pane == _WhoPane.place,
              onSelected: widget.readOnly
                  ? null
                  : (_) => setState(() {
                        _pane = _pane == _WhoPane.place ? null : _WhoPane.place;
                        _manualMode = _pane == _WhoPane.place;
                      }),
            ),
            ActionChip(
              avatar: const Icon(Icons.home_work_outlined, size: 16),
              label: const Text('Foyers'),
              onPressed: () async {
                await showHouseholdsSheet(context);
                if (!mounted) return;
                setState(() {
                  _homes = [...HouseholdService.instance.homes];
                  _placeSuggestions = {
                    ..._placeSuggestions,
                    ...SocialDirectoryCache.instance.places,
                  }.toList();
                });
              },
            ),
          ],
        ),
        if (_pane == _WhoPane.person) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _people)
                _personChip(
                  label: m.label,
                  selected: _isSelectedUser(m.userId),
                  avatarUrl: m.avatarUrl,
                  accent: m.accentColor,
                  onTap: widget.readOnly
                      ? null
                      : () => _selectUser(m.userId, m.label),
                ),
              for (final name in SocialDirectoryCache.instance.people)
                if (!_people.any(
                  (p) => p.label.toLowerCase() == name.toLowerCase(),
                ))
                  FilterChip(
                    avatar: const Icon(Icons.person_outline, size: 16),
                    label: Text(name),
                    selected: (widget.holderLabel ?? '').toLowerCase().contains(
                      name.toLowerCase(),
                    ),
                    onSelected: widget.readOnly
                        ? null
                        : (_) => _applySuggestion(name),
                  ),
            ],
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            _manualField('Nouvelle personne'),
          ],
        ],
        if (_pane == _WhoPane.place) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final home in _homes)
                FilterChip(
                  avatar: const Icon(Icons.place_outlined, size: 16),
                  label: Text(home.place),
                  selected: _isHomeSelected(home),
                  onSelected: widget.readOnly ? null : (_) => _selectHome(home),
                ),
              for (final place in {
                ..._placeSuggestions,
                ...SocialDirectoryCache.instance.places,
              })
                InputChip(
                  avatar: const Icon(Icons.place_outlined, size: 16),
                  label: Text(
                    holderLabelStorageValue(place),
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _applySuggestion(place),
                  onDeleted: () => _removeSuggestion(place),
                ),
            ],
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            _manualField('Nouveau lieu'),
          ],
        ],
      ],
    );
  }

  Widget _manualField(String label) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _manualController,
            focusNode: _manualFocusNode,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
            ),
            onSubmitted: (_) => _submitManual(),
          ),
        ),
        IconButton(
          onPressed: _submitManual,
          icon: const Icon(Icons.check),
          tooltip: 'Valider',
        ),
      ],
    );
  }

  Widget _personChip({
    required String label,
    required bool selected,
    required String? avatarUrl,
    required String? accent,
    required VoidCallback? onTap,
    IconData? icon,
  }) {
    return FilterChip(
      avatar: icon != null
          ? Icon(icon, size: 16)
          : ProfileAvatar(
              avatarUrl: avatarUrl,
              accentColorHex: accent,
              fallbackInitial: label,
              radius: 10,
            ),
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap(),
    );
  }
}
