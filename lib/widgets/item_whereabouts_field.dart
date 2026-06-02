import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/group_service.dart';

enum _WhereMode { atPlace, lent }

/// Groupe : chez un membre / autre (ami ou nom) / prêté.
class ItemWhereaboutsField extends StatefulWidget {
  const ItemWhereaboutsField({
    super.key,
    required this.groupId,
    required this.locationUserId,
    required this.holderLabel,
    required this.customHolderName,
    required this.isOnLoan,
    required this.loanedToId,
    required this.loanedToName,
    required this.onChanged,
    this.readOnly = false,
  });

  final String groupId;
  final String? locationUserId;
  final String? holderLabel;
  final String? customHolderName;
  final bool isOnLoan;
  final String? loanedToId;
  final String? loanedToName;
  final bool readOnly;
  final void Function({
    String? locationUserId,
    String? holderLabel,
    String? customHolderName,
    bool clearHolder,
    String? loanedToId,
    String? loanedToName,
    bool clearLoan,
  }) onChanged;

  @override
  State<ItemWhereaboutsField> createState() => _ItemWhereaboutsFieldState();
}

class _ItemWhereaboutsFieldState extends State<ItemWhereaboutsField> {
  final _groupService = GroupService();
  final _friendService = FriendService();
  final _customController = TextEditingController();
  final _loanExternalController = TextEditingController();

  List<({String id, String username})> _members = [];
  List<Map<String, dynamic>> _friends = [];
  _WhereMode _mode = _WhereMode.atPlace;
  String? _memberId;
  bool _otherExpanded = false;
  bool _otherManual = false;
  String? _otherFriendId;
  String? _loanFriendId;
  bool _loanExternal = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _customController.text = widget.customHolderName ?? '';
    _loanExternalController.text =
        widget.loanedToId == null ? (widget.loanedToName ?? '') : '';
    _hydrate();
    _load();
  }

  @override
  void didUpdateWidget(ItemWhereaboutsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOnLoan != widget.isOnLoan ||
        oldWidget.locationUserId != widget.locationUserId ||
        oldWidget.customHolderName != widget.customHolderName) {
      _hydrate();
    }
  }

  void _hydrate() {
    if (widget.isOnLoan) {
      _mode = _WhereMode.lent;
      _loanFriendId = widget.loanedToId;
      _loanExternal = widget.loanedToId == null &&
          (widget.loanedToName?.trim().isNotEmpty ?? false);
      return;
    }
    _mode = _WhereMode.atPlace;
    if (widget.customHolderName?.trim().isNotEmpty == true) {
      _otherExpanded = true;
      _otherManual = true;
      _memberId = null;
    } else {
      _memberId = widget.locationUserId;
      _otherExpanded = false;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _groupService.fetchMembers(widget.groupId);
      _members = [
        for (final row in rows)
          (
            id: row['profile_id'] as String,
            username: (row['profiles'] as Map?)?['username'] as String? ??
                'Membre',
          ),
      ];
      _friends = await _friendService.fetchFriends();
    } catch (_) {
      _members = [];
      _friends = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _customController.dispose();
    _loanExternalController.dispose();
    super.dispose();
  }

  void _emitMember(String? id) {
    setState(() {
      _otherExpanded = false;
      _otherManual = false;
      _memberId = id;
    });
    if (id == null) {
      widget.onChanged(clearHolder: true, clearLoan: true);
      return;
    }
    final m = _members.firstWhere((e) => e.id == id);
    widget.onChanged(
      locationUserId: id,
      holderLabel: 'Chez ${m.username}',
      customHolderName: null,
      clearLoan: true,
    );
  }

  void _emitOtherFriend() {
    if (_otherFriendId == null) return;
    final f = _friends.firstWhere(
      (x) => x['profile_id'] == _otherFriendId,
      orElse: () => {},
    );
    final name = f['username'] as String? ?? 'Ami';
    widget.onChanged(
      locationUserId: _otherFriendId,
      holderLabel: 'Chez $name',
      customHolderName: null,
      clearLoan: true,
    );
  }

  void _emitOtherManual() {
    final name = _customController.text.trim();
    if (name.isEmpty) {
      widget.onChanged(clearHolder: true, clearLoan: true);
      return;
    }
    widget.onChanged(
      locationUserId: null,
      holderLabel: 'Chez $name',
      customHolderName: name,
      clearLoan: true,
    );
  }

  void _emitLoan() {
    if (_loanExternal) {
      final name = _loanExternalController.text.trim();
      if (name.isEmpty) return;
      widget.onChanged(
        clearHolder: true,
        loanedToId: null,
        loanedToName: name,
      );
      return;
    }
    if (_loanFriendId == null) return;
    final f = _friends.firstWhere(
      (x) => x['profile_id'] == _loanFriendId,
      orElse: () => {},
    );
    widget.onChanged(
      clearHolder: true,
      loanedToId: _loanFriendId,
      loanedToName: f['username'] as String? ?? 'Ami',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Où est l\'objet ?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<_WhereMode>(
          segments: const [
            ButtonSegment(
              value: _WhereMode.atPlace,
              label: Text('Chez'),
              icon: Icon(Icons.home_outlined, size: 18),
            ),
            ButtonSegment(
              value: _WhereMode.lent,
              label: Text('Prêté'),
              icon: Icon(Icons.handshake_outlined, size: 18),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: widget.readOnly
              ? null
              : (s) {
                  setState(() => _mode = s.first);
                  if (_mode == _WhereMode.atPlace && _memberId != null) {
                    _emitMember(_memberId);
                  } else if (_mode == _WhereMode.lent) {
                    _emitLoan();
                  }
                },
        ),
        if (_mode == _WhereMode.atPlace) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._members.map(
                (m) => ChoiceChip(
                  label: Text(m.username),
                  selected: !_otherExpanded && _memberId == m.id,
                  onSelected: widget.readOnly
                      ? null
                      : (_) => _emitMember(m.id),
                ),
              ),
              ChoiceChip(
                label: const Text('Autre'),
                selected: _otherExpanded,
                onSelected: widget.readOnly
                    ? null
                    : (_) {
                        setState(() {
                          _otherExpanded = true;
                          _memberId = null;
                        });
                        if (_otherManual) {
                          _emitOtherManual();
                        } else if (_otherFriendId != null) {
                          _emitOtherFriend();
                        }
                      },
              ),
            ],
          ),
          if (_otherExpanded) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nom hors app / famille'),
              value: _otherManual,
              onChanged: widget.readOnly
                  ? null
                  : (v) {
                      setState(() => _otherManual = v);
                      if (v) {
                        _emitOtherManual();
                      } else if (_otherFriendId != null) {
                        _emitOtherFriend();
                      }
                    },
            ),
            if (_otherManual)
              TextField(
                controller: _customController,
                readOnly: widget.readOnly,
                decoration: const InputDecoration(
                  labelText: 'Chez (nom libre)',
                ),
                onChanged: widget.readOnly ? null : (_) => _emitOtherManual(),
              )
            else if (_friends.isEmpty)
              Text(
                'Aucun ami — utilise le nom libre ou ajoute un ami.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _otherFriendId,
                decoration: const InputDecoration(labelText: 'Ami'),
                items: _friends
                    .map(
                      (f) => DropdownMenuItem(
                        value: f['profile_id'] as String,
                        child: Text(f['username'] as String),
                      ),
                    )
                    .toList(),
                onChanged: widget.readOnly
                    ? null
                    : (id) {
                        setState(() => _otherFriendId = id);
                        _emitOtherFriend();
                      },
              ),
          ],
        ],
        if (_mode == _WhereMode.lent) ...[
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hors application'),
            value: _loanExternal,
            onChanged: widget.readOnly
                ? null
                : (v) {
                    setState(() => _loanExternal = v);
                    _emitLoan();
                  },
          ),
          if (_loanExternal)
            TextField(
              controller: _loanExternalController,
              readOnly: widget.readOnly,
              decoration: const InputDecoration(labelText: 'Prêté à'),
              onChanged: widget.readOnly ? null : (_) => _emitLoan(),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _loanFriendId,
              decoration: const InputDecoration(labelText: 'Ami'),
              items: _friends
                  .map(
                    (f) => DropdownMenuItem(
                      value: f['profile_id'] as String,
                      child: Text(f['username'] as String),
                    ),
                  )
                  .toList(),
              onChanged: widget.readOnly
                  ? null
                  : (id) {
                      setState(() => _loanFriendId = id);
                      _emitLoan();
                    },
            ),
        ],
      ],
    );
  }
}
