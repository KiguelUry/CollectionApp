import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/holder_place_history_service.dart';
import '../utils/holder_label_utils.dart';

/// « Chez qui ? » — membre, ami ou saisie libre. La persistance est gérée par le parent via [onChanged].
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

  const _MemberOption({required this.userId, required this.label});
}

class _GroupSection {
  final String id;
  final String name;
  final List<_MemberOption> members;

  const _GroupSection({
    required this.id,
    required this.name,
    required this.members,
  });
}

class _CompactWhereaboutsDropdownState
    extends State<CompactWhereaboutsDropdown> {
  final _groupService = GroupService();
  final _friendService = FriendService();
  final _manualFocusNode = FocusNode();
  late TextEditingController _manualController;

  String? _meUserId;
  List<_GroupSection> _groupSections = [];
  List<_MemberOption> _friendOptions = [];
  List<String> _placeSuggestions = [];
  bool _initialLoading = true;
  bool _defaultApplied = false;
  bool _manualMode = false;

  bool get _isManualHolder =>
      widget.locationUserId == null &&
      widget.holderLabel != null &&
      widget.holderLabel!.trim().isNotEmpty;

  String? get _personalUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
    _load(initial: true);
    _loadPlaceSuggestions();
  }

  void _syncFromWidget() {
    _manualMode = _isManualHolder;
    _manualController = TextEditingController(
      text: _isManualHolder
          ? holderLabelStorageValue(widget.holderLabel!.trim())
          : '',
    );
  }

  @override
  void didUpdateWidget(CompactWhereaboutsDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final groupsChanged = !_setEquals(
      oldWidget.selectedGroupIds,
      widget.selectedGroupIds,
    );
    if (groupsChanged) {
      _load(initial: false);
      _loadPlaceSuggestions();
    }

    if (_manualMode || _manualFocusNode.hasFocus) return;

    if (oldWidget.holderLabel != widget.holderLabel ||
        oldWidget.locationUserId != widget.locationUserId) {
      if (_isManualHolder) {
        _manualMode = true;
        final stripped = holderLabelStorageValue(widget.holderLabel!.trim());
        if (_manualController.text != stripped) {
          _manualController.text = stripped;
        }
      } else {
        _manualMode = false;
        if (widget.locationUserId != null) {
          _manualController.clear();
        }
      }
    }
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  void dispose() {
    _manualFocusNode.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaceSuggestions() async {
    final ids = widget.selectedGroupIds;
    final places = await HolderPlaceHistoryService.loadForGroups(
      ids,
      personalUserId: ids.isEmpty ? _personalUserId : null,
    );
    if (!mounted) return;
    setState(() => _placeSuggestions = places);
  }

  void _applyDefaultIfNeeded() {
    if (!widget.applyDefaultIfEmpty || widget.readOnly || _defaultApplied) {
      return;
    }
    if (_isManualHolder || _manualMode) return;
    if (widget.locationUserId != null) return;
    final me = _meUserId;
    if (me == null) return;
    _defaultApplied = true;
    widget.onChanged(
      locationUserId: me,
      holderLabel: 'Chez moi',
    );
  }

  Future<void> _load({required bool initial}) async {
    if (initial) {
      setState(() => _initialLoading = true);
    }
    final me = Supabase.instance.client.auth.currentUser?.id;
    final groupSections = <_GroupSection>[];

    for (final gid in widget.selectedGroupIds) {
      CollectionGroup? g;
      for (final x in widget.groups) {
        if (x.id == gid) {
          g = x;
          break;
        }
      }
      if (g == null) continue;
      final members = <_MemberOption>[];
      try {
        final rows = await _groupService.fetchMembers(gid);
        for (final row in rows) {
          final pid = row['profile_id'] as String?;
          if (pid == null || pid.isEmpty || pid == me) continue;
          final username =
              (row['profiles'] as Map?)?['username'] as String? ?? 'Membre';
          members.add(_MemberOption(userId: pid, label: username));
        }
      } catch (_) {}
      groupSections.add(
        _GroupSection(id: gid, name: g.name, members: members),
      );
    }

    final friendOpts = <_MemberOption>[];
    try {
      final friends = await _friendService.fetchFriends();
      for (final f in friends) {
        final pid = f['profile_id'] as String?;
        if (pid == null || pid.isEmpty || pid == me) continue;
        friendOpts.add(
          _MemberOption(
            userId: pid,
            label: f['username'] as String? ?? 'Ami',
          ),
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _meUserId = me;
      _groupSections = groupSections;
      _friendOptions = friendOpts;
      _initialLoading = false;
    });
    if (initial) _applyDefaultIfNeeded();
  }

  bool _isSelectedUser(String userId) =>
      !_manualMode && !_isManualHolder && widget.locationUserId == userId;

  bool get _isManualSelected => _manualMode || _isManualHolder;

  void _selectUser(String userId, String label) {
    if (widget.readOnly) return;
    setState(() {
      _manualMode = false;
      _manualFocusNode.unfocus();
    });
    widget.onChanged(
      locationUserId: userId,
      holderLabel: label == 'Chez moi' ? 'Chez moi' : 'Chez $label',
    );
  }

  void _selectManual() {
    if (widget.readOnly) return;
    setState(() {
      _manualMode = true;
      if (!_isManualHolder) _manualController.clear();
    });
  }

  void _applySuggestion(String raw) {
    _manualController.text = raw;
    _submitManual(skipConfirm: true);
  }

  Future<void> _submitManual({bool skipConfirm = false}) async {
    final t = _manualController.text.trim();
    if (t.isEmpty) return;

    final preview = formatManualHolderLabel(t);
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

  Widget _selectionTile({
    required String title,
    required bool selected,
    required VoidCallback? onTap,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        icon ?? Icons.person_outline,
        size: 20,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : null,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: scheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Chez qui ?',
            isDense: true,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_meUserId != null)
                _selectionTile(
                  title: 'Chez moi',
                  selected: _isSelectedUser(_meUserId!),
                  onTap: widget.readOnly
                      ? null
                      : () => _selectUser(_meUserId!, 'Chez moi'),
                  icon: Icons.home_outlined,
                ),
              for (final section in _groupSections)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: false,
                    title: Text(
                      section.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: section.members.isEmpty
                        ? [
                            const Padding(
                              padding: EdgeInsets.only(left: 16, bottom: 8),
                              child: Text(
                                'Aucun autre membre',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ]
                        : section.members
                            .map(
                              (m) => _selectionTile(
                                title: 'Chez ${m.label}',
                                selected: _isSelectedUser(m.userId),
                                onTap: widget.readOnly
                                    ? null
                                    : () => _selectUser(m.userId, m.label),
                              ),
                            )
                            .toList(),
                  ),
                ),
              if (_friendOptions.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: false,
                    title: const Text(
                      'Amis',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: _friendOptions
                        .map(
                          (m) => _selectionTile(
                            title: 'Chez ${m.label}',
                            selected: _isSelectedUser(m.userId),
                            onTap: widget.readOnly
                                ? null
                                : () => _selectUser(m.userId, m.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
              _selectionTile(
                title: 'Autre (personne ou lieu)',
                selected: _isManualSelected,
                onTap: widget.readOnly ? null : _selectManual,
                icon: Icons.edit_outlined,
              ),
            ],
          ),
        ),
        if (_isManualSelected && !widget.readOnly) ...[
          const SizedBox(height: 8),
          if (_placeSuggestions.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _placeSuggestions.map((place) {
                final label = formatManualHolderLabel(place);
                return InputChip(
                  label: Text(
                    label,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _applySuggestion(place),
                  onDeleted: () => _removeSuggestion(place),
                  deleteIcon: const Icon(Icons.close, size: 16),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  focusNode: _manualFocusNode,
                  enableInteractiveSelection: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Nom ou lieu',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submitManual(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _submitManual,
                icon: const Icon(Icons.check),
                tooltip: 'Valider',
              ),
            ],
          ),
        ],
      ],
    );
  }
}
