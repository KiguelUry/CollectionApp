import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../utils/holder_label_utils.dart';

/// « Chez ? » compact — membres uniques, saisie manuelle, défaut « Chez moi ».
class CompactWhereaboutsDropdown extends StatefulWidget {
  final List<CollectionGroup> groups;
  final Set<String> selectedGroupIds;
  final String? locationUserId;
  final String? holderLabel;
  final bool readOnly;
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

  List<_MemberOption> _options = [];
  bool _initialLoading = true;
  bool _defaultApplied = false;
  late TextEditingController _manualController;
  bool _manualMode = false;

  bool get _isManualHolder =>
      widget.locationUserId == null &&
      widget.holderLabel != null &&
      widget.holderLabel!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _syncManualStateFromWidget();
    _load(initial: true);
  }

  void _syncManualStateFromWidget() {
    _manualMode = _isManualHolder;
    _manualController = TextEditingController(
      text: _manualMode
          ? widget.holderLabel!
              .trim()
              .replaceFirst(RegExp(r'^Chez\s+', caseSensitive: false), '')
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
    }
    if (oldWidget.holderLabel != widget.holderLabel ||
        oldWidget.locationUserId != widget.locationUserId) {
      final manual = _isManualHolder;
      if (manual) {
        _manualMode = true;
        final stripped = widget.holderLabel!
            .trim()
            .replaceFirst(RegExp(r'^Chez\s+', caseSensitive: false), '');
        if (_manualController.text != stripped) {
          _manualController.text = stripped;
        }
      } else if (_manualMode && widget.locationUserId != null) {
        _manualMode = false;
      }
    }
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  void _applyDefaultIfNeeded() {
    if (widget.readOnly || _defaultApplied || _isManualHolder) return;
    if (widget.locationUserId != null) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    _defaultApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onChanged(
        locationUserId: me,
        holderLabel: 'Chez moi',
      );
    });
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
      setState(() => _manualMode = true);
      return;
    }
    setState(() => _manualMode = false);
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

  Future<void> _submitManual() async {
    final t = _manualController.text.trim();
    if (t.isEmpty) return;

    final preview = formatManualHolderLabel(t);
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

    setState(() => _manualMode = true);
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
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
