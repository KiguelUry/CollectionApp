import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/holder_place_history_service.dart';
import '../utils/holder_label_utils.dart';

/// « Chez ? » — membre, ami ou saisie libre. La persistance est gérée par le parent via [onChanged].
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
  final String value;
  final String label;
  final bool isHeader;

  const _MemberOption({
    required this.value,
    required this.label,
    this.isHeader = false,
  });
}

class _CompactWhereaboutsDropdownState
    extends State<CompactWhereaboutsDropdown> {
  final _groupService = GroupService();
  final _friendService = FriendService();
  final _manualFocusNode = FocusNode();
  late TextEditingController _manualController;

  List<_MemberOption> _options = [];
  List<String> _placeSuggestions = [];
  bool _initialLoading = true;
  bool _defaultApplied = false;
  bool _manualMode = false;

  bool get _isManualHolder =>
      widget.locationUserId == null &&
      widget.holderLabel != null &&
      widget.holderLabel!.trim().isNotEmpty;

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
    if (ids.isEmpty) {
      if (mounted) setState(() => _placeSuggestions = []);
      return;
    }
    final places = await HolderPlaceHistoryService.loadForGroups(ids);
    if (!mounted) return;
    setState(() => _placeSuggestions = places);
  }

  void _applyDefaultIfNeeded() {
    if (!widget.applyDefaultIfEmpty || widget.readOnly || _defaultApplied) {
      return;
    }
    if (_isManualHolder || _manualMode) return;
    if (widget.locationUserId != null) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
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
    final seenUserIds = <String>{};
    final opts = <_MemberOption>[];

    void addUser(String userId, String label) {
      if (seenUserIds.contains(userId)) return;
      seenUserIds.add(userId);
      opts.add(_MemberOption(value: 'user:$userId', label: label));
    }

    if (me != null) {
      addUser(me, 'Chez moi');
    }

    for (final gid in widget.selectedGroupIds) {
      CollectionGroup? g;
      for (final x in widget.groups) {
        if (x.id == gid) {
          g = x;
          break;
        }
      }
      if (g == null) continue;
      opts.add(
        _MemberOption(value: 'hdr:$gid', label: g.name, isHeader: true),
      );
      try {
        final rows = await _groupService.fetchMembers(gid);
        for (final row in rows) {
          final pid = row['profile_id'] as String?;
          if (pid == null || pid.isEmpty) continue;
          final username =
              (row['profiles'] as Map?)?['username'] as String? ?? 'Membre';
          addUser(pid, username);
        }
      } catch (_) {}
    }

    try {
      final friends = await _friendService.fetchFriends();
      final friendOpts = <_MemberOption>[];
      for (final f in friends) {
        final pid = f['profile_id'] as String?;
        if (pid == null || pid.isEmpty || seenUserIds.contains(pid)) continue;
        seenUserIds.add(pid);
        friendOpts.add(
          _MemberOption(
            value: 'user:$pid',
            label: f['username'] as String? ?? 'Ami',
          ),
        );
      }
      if (friendOpts.isNotEmpty) {
        opts.add(
          const _MemberOption(
            value: 'hdr:friends',
            label: 'Amis',
            isHeader: true,
          ),
        );
        opts.addAll(friendOpts);
      }
    } catch (_) {}

    opts.add(
      const _MemberOption(value: 'manual', label: 'Autre (saisie libre)'),
    );

    if (!mounted) return;
    setState(() {
      _options = opts;
      _initialLoading = false;
    });
    if (initial) _applyDefaultIfNeeded();
  }

  String? get _dropdownValue {
    if (_manualMode || _isManualHolder) return 'manual';
    final uid = widget.locationUserId;
    if (uid == null) return null;
    final v = 'user:$uid';
    final matches = _options.where((o) => !o.isHeader && o.value == v).length;
    if (matches == 1) return v;
    return null;
  }

  void _onDropdownChanged(String? v) {
    if (v == null || v.startsWith('hdr:')) return;
    if (v == 'manual') {
      setState(() {
        _manualMode = true;
        if (!_isManualHolder) _manualController.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _manualFocusNode.requestFocus();
      });
      return;
    }
    setState(() {
      _manualMode = false;
      _manualFocusNode.unfocus();
    });
    if (v.startsWith('user:')) {
      final uid = v.substring(5);
      final opt = _options.firstWhere(
        (o) => o.value == v,
        orElse: () => _MemberOption(value: v, label: 'Membre'),
      );
      widget.onChanged(
        locationUserId: uid,
        holderLabel: opt.label == 'Chez moi' ? 'Chez moi' : 'Chez ${opt.label}',
      );
    }
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
    );
    await _loadPlaceSuggestions();
    if (!mounted) return;
    widget.onChanged(holderLabel: preview, manualHolder: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final selectable = _options.where((o) => !o.isHeader).toList();
    final value = _dropdownValue;
    final validValue = value != null &&
        selectable.where((o) => o.value == value).length == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Chez qui ?',
            isDense: true,
            helperText: _isManualHolder && !_manualMode
                ? widget.holderLabel
                : null,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: validValue ? value : null,
              items: _options.map((o) {
                if (o.isHeader) {
                  return DropdownMenuItem<String>(
                    value: o.value,
                    enabled: false,
                    child: Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                }
                return DropdownMenuItem<String>(
                  value: o.value,
                  child: Text(o.label),
                );
              }).toList(),
              onChanged: widget.readOnly ? null : _onDropdownChanged,
            ),
          ),
        ),
        if ((_manualMode || _isManualHolder) && !widget.readOnly) ...[
          const SizedBox(height: 8),
          if (_placeSuggestions.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _placeSuggestions.map((place) {
                final label = formatManualHolderLabel(place);
                return ActionChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _applySuggestion(place),
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
