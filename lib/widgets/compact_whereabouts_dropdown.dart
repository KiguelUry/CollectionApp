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
import 'profile_avatar.dart';

/// « Où se trouve l'objet ? » — chez moi / personne / lieu.
class CompactWhereaboutsDropdown extends StatefulWidget {
  final List<CollectionGroup> groups;
  final Set<String> selectedGroupIds;
  final String? locationUserId;
  final String? holderLabel;
  final bool readOnly;
  final bool applyDefaultIfEmpty;
  /// Prêt actif : ne pas cocher « Chez moi » (domicile mémorisé, objet ailleurs).
  final bool loanActive;
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
    this.loanActive = false,
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
  final _personSearch = TextEditingController();

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
    // Champ « Nouveau lieu » toujours vide (pas de pré-remplissage).
    _manualController = TextEditingController();
    _meUserId = _personalUserId;
    _seedFromCache();
    _syncPaneFromProps();
    unawaited(_loadRemote());
  }

  @override
  void didUpdateWidget(covariant CompactWhereaboutsDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationUserId != widget.locationUserId ||
        oldWidget.holderLabel != widget.holderLabel ||
        oldWidget.loanActive != widget.loanActive) {
      _syncPaneFromProps();
    }
  }

  /// Infère Personne / Lieu / Chez moi depuis les props (ex. « Braine l'Alleud »).
  void _syncPaneFromProps() {
    if (widget.loanActive) return;
    final me = _meUserId;
    if (widget.locationUserId != null &&
        me != null &&
        widget.locationUserId == me) {
      _pane = null;
      _manualMode = false;
      return;
    }
    if (widget.locationUserId != null &&
        me != null &&
        widget.locationUserId != me) {
      _pane = _WhoPane.person;
      _manualMode = false;
      return;
    }
    final label = (widget.holderLabel ?? '').trim();
    if (label.isEmpty || label == '—') {
      _pane = null;
      return;
    }
    final lower = label.toLowerCase();
    if (lower == 'chez moi') {
      _pane = null;
      _manualMode = false;
      return;
    }
    if (RegExp(r'^(à|a|en|au)\s+', caseSensitive: false).hasMatch(label) ||
        _homes.any((h) => _normPlace(h.place) == _normPlace(label)) ||
        _placeSuggestions.any((p) => _normPlace(p) == _normPlace(label))) {
      _pane = _WhoPane.place;
      _manualMode = true;
      return;
    }
    if (lower.startsWith('chez ') ||
        _people.any(
          (p) =>
              p.label.toLowerCase() == lower ||
              p.label.toLowerCase() ==
                  holderLabelStorageValue(label).toLowerCase(),
        )) {
      _pane = _WhoPane.person;
      _manualMode = true;
      return;
    }
    // Libellé libre sans préfixe (ex. ville) → Lieu.
    _pane = _WhoPane.place;
    _manualMode = true;
  }

  String? get _destinationArrowLabel {
    if (widget.loanActive) return null;
    final me = _meUserId;
    if (widget.locationUserId != null &&
        me != null &&
        widget.locationUserId == me) {
      return null;
    }
    if (widget.locationUserId != null &&
        me != null &&
        widget.locationUserId != me) {
      final match = _people.where((p) => p.userId == widget.locationUserId);
      if (match.isNotEmpty) return match.first.label;
      final hl = (widget.holderLabel ?? '').trim();
      return hl.isEmpty ? null : holderLabelStorageValue(hl);
    }
    final label = (widget.holderLabel ?? '').trim();
    if (label.isEmpty || label == '—' || label.toLowerCase() == 'chez moi') {
      return null;
    }
    return holderLabelStorageValue(label);
  }

  static bool _isJunkPlace(String raw) {
    final n = raw.trim().toLowerCase();
    return n.isEmpty ||
        n == 'inconnu' ||
        n == 'unknown' ||
        n == 'non renseigné' ||
        n == 'non renseignée' ||
        n == '—' ||
        n == '-';
  }

  static String _normPlace(String raw) =>
      holderLabelStorageValue(raw).trim().toLowerCase();

  /// Puces lieu uniques (foyers + suggestions), sans doublon ni « Inconnu ».
  List<({String label, Household? home, bool isHome})> _dedupedPlaceChips() {
    final out = <({String label, Household? home, bool isHome})>[];
    final seen = <String>{};
    for (final home in _homes) {
      final key = _normPlace(home.place);
      if (_isJunkPlace(key) || !seen.add(key)) continue;
      out.add((label: home.place, home: home, isHome: true));
    }
    for (final place in {..._placeSuggestions, ...SocialDirectoryCache.instance.places}) {
      final key = _normPlace(place);
      if (_isJunkPlace(key) || !seen.add(key)) continue;
      out.add((
        label: holderLabelStorageValue(place),
        home: null,
        isHome: false,
      ));
    }
    return out;
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

  List<_MemberOption> _filteredPeople() {
    final q = _personSearch.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _people
        : _people
            .where((p) => p.label.toLowerCase().contains(q))
            .toList();
    return list;
  }

  @override
  void dispose() {
    _personSearch.dispose();
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
      _syncPaneFromProps();
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
    // Foyer lié (Papa/Maman/Zoé → Braine-l'Alleud) : affiche le lieu sur la tuile.
    Household? linked;
    final lower = label.trim().toLowerCase();
    for (final home in _homes) {
      if (home.people.any((p) => p.trim().toLowerCase() == lower)) {
        linked = home;
        break;
      }
    }
    widget.onChanged(
      locationUserId: userId,
      holderLabel: linked?.placeLabel ?? label,
    );
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
    setState(() {
      _manualMode = true;
      _manualController.clear();
    });
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
    final bare = holderLabelStorageValue(place).trim();
    // Optimistic : disparaît tout de suite (plus de réapparition via cache social).
    setState(() {
      _placeSuggestions = [
        for (final p in _placeSuggestions)
          if (_normPlace(p) != _normPlace(place) &&
              _normPlace(p) != _normPlace(bare))
            p,
      ];
    });
    SocialDirectoryCache.instance.removePlace(place);
    if (_normPlace(widget.holderLabel ?? '') == _normPlace(place) ||
        _normPlace(widget.holderLabel ?? '') == _normPlace(bare)) {
      widget.onChanged(clearHolder: true, manualHolder: true);
    }
    unawaited(
      HolderPlaceHistoryService.removeForGroups(
        widget.selectedGroupIds,
        place,
        personalUserId:
            widget.selectedGroupIds.isEmpty ? _personalUserId : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dest = _destinationArrowLabel;
    final chezMoiSelected = !widget.loanActive &&
        _meUserId != null &&
        _isSelectedUser(_meUserId!) &&
        _pane == null;
    final personSelected = !widget.loanActive && _pane == _WhoPane.person;
    final placeSelected = !widget.loanActive && _pane == _WhoPane.place;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Où se trouve l\'objet ?',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (dest != null && dest.isNotEmpty) ...[
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  dest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Onglets segmentés (distincts des puces de choix).
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                if (_meUserId != null)
                  Expanded(
                    child: _WhoTab(
                      icon: Icons.home_outlined,
                      label: 'Chez moi',
                      selected: chezMoiSelected,
                      onTap: widget.readOnly
                          ? null
                          : () {
                              setState(() => _pane = null);
                              _selectUser(_meUserId!, 'Chez moi');
                            },
                    ),
                  ),
                Expanded(
                  child: _WhoTab(
                    icon: Icons.person_outline,
                    label: 'Personne',
                    selected: personSelected,
                    onTap: widget.readOnly
                        ? null
                        : () => setState(() {
                              _pane = _pane == _WhoPane.person
                                  ? null
                                  : _WhoPane.person;
                              _manualMode = _pane == _WhoPane.person;
                            }),
                  ),
                ),
                Expanded(
                  child: _WhoTab(
                    icon: Icons.place_outlined,
                    label: 'Lieu',
                    selected: placeSelected,
                    onTap: widget.readOnly
                        ? null
                        : () => setState(() {
                              _pane =
                                  _pane == _WhoPane.place ? null : _WhoPane.place;
                              _manualMode = _pane == _WhoPane.place;
                            }),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.loanActive) ...[
          const SizedBox(height: 8),
          FilterChip(
            avatar: Icon(Icons.handshake_outlined,
                size: 16, color: Colors.blue.shade700),
            label: const Text('Prêté'),
            selected: true,
            selectedColor: Colors.blue.withValues(alpha: 0.22),
            checkmarkColor: Colors.blue.shade700,
            onSelected: null,
          ),
        ],
        if (_pane == _WhoPane.person) ...[
          const SizedBox(height: 10),
          Text(
            'Choisir une personne :',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (!widget.readOnly)
            TextField(
              controller: _personSearch,
              decoration: const InputDecoration(
                hintText: 'Rechercher un ami ou saisir un nom…',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isEmpty) return;
                _MemberOption? match;
                for (final p in _people) {
                  if (p.label.toLowerCase() == t.toLowerCase()) {
                    match = p;
                    break;
                  }
                }
                if (match != null) {
                  _selectUser(match.userId, match.label);
                } else {
                  _applySuggestion(t);
                }
                _personSearch.clear();
              },
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _filteredPeople().take(5))
                _personChip(
                  label: m.label,
                  selected: _isSelectedUser(m.userId),
                  avatarUrl: m.avatarUrl,
                  accent: m.accentColor,
                  onTap: widget.readOnly
                      ? null
                      : () => _selectUser(m.userId, m.label),
                ),
            ],
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            _manualField('Nouvelle personne'),
          ],
        ],
        if (_pane == _WhoPane.place) ...[
          const SizedBox(height: 10),
          Text(
            'Choisir un lieu :',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chip in _dedupedPlaceChips())
                if (chip.isHome && chip.home != null)
                  FilterChip(
                    avatar: const Icon(Icons.place_outlined, size: 16),
                    label: Text(chip.label),
                    selected: _isHomeSelected(chip.home!),
                    onSelected:
                        widget.readOnly ? null : (_) => _selectHome(chip.home!),
                  )
                else
                  InputChip(
                    avatar: const Icon(Icons.place_outlined, size: 16),
                    label: Text(
                      chip.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    selected: _normPlace(widget.holderLabel ?? '') ==
                        _normPlace(chip.label),
                    onPressed: widget.readOnly
                        ? null
                        : () => _applySuggestion(chip.label),
                    onDeleted: widget.readOnly
                        ? null
                        : () => _removeSuggestion(chip.label),
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

class _WhoTab extends StatelessWidget {
  const _WhoTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.surfaceContainerHighest
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
