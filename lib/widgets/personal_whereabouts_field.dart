import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/friend_service.dart';
import '../services/profile_service.dart';

/// Objet perso : chez moi, chez un ami, ou nom libre.
class PersonalWhereaboutsField extends StatefulWidget {
  const PersonalWhereaboutsField({
    super.key,
    required this.locationUserId,
    required this.customHolderName,
    required this.onChanged,
    this.readOnly = false,
  });

  final String? locationUserId;
  final String? customHolderName;
  final bool readOnly;
  final void Function({
    String? locationUserId,
    String? holderLabel,
    String? customHolderName,
    bool clearHolder,
  }) onChanged;

  @override
  State<PersonalWhereaboutsField> createState() =>
      _PersonalWhereaboutsFieldState();
}

class _PersonalWhereaboutsFieldState extends State<PersonalWhereaboutsField> {
  final _friendService = FriendService();
  final _manualController = TextEditingController();

  String? _myUserId;
  String _myUsername = 'Moi';
  List<Map<String, dynamic>> _friends = [];
  bool _useManual = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _manualController.text = widget.customHolderName ?? '';
    _useManual = widget.customHolderName?.trim().isNotEmpty == true &&
        widget.locationUserId == null;
    _load();
  }

  Future<void> _load() async {
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    try {
      final profile = await ProfileService().fetchCurrentProfile();
      _myUsername = profile.username;
      _friends = await _friendService.fetchFriends();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  bool get _isAtMe =>
      !_useManual &&
      widget.locationUserId != null &&
      widget.locationUserId == _myUserId;

  void _selectMe() {
    setState(() => _useManual = false);
    widget.onChanged(
      locationUserId: _myUserId,
      holderLabel: 'Chez $_myUsername',
      customHolderName: null,
    );
  }

  void _selectFriend(String? friendId, String username) {
    setState(() => _useManual = false);
    if (friendId == null) {
      widget.onChanged(clearHolder: true);
      return;
    }
    widget.onChanged(
      locationUserId: friendId,
      holderLabel: 'Chez $username',
      customHolderName: null,
    );
  }

  void _emitManual() {
    final name = _manualController.text.trim();
    if (name.isEmpty) {
      widget.onChanged(clearHolder: true);
      return;
    }
    widget.onChanged(
      locationUserId: null,
      holderLabel: 'Chez $name',
      customHolderName: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    String? dropdownValue;
    if (_useManual) {
      dropdownValue = '__manual__';
    } else if (_isAtMe) {
      dropdownValue = '__me__';
    } else if (widget.locationUserId != null) {
      dropdownValue = widget.locationUserId;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Où est l\'objet ?',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ChoiceChip(
          label: Text('Chez $_myUsername'),
          selected: _isAtMe,
          onSelected: widget.readOnly ? null : (_) => _selectMe(),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: dropdownValue,
          decoration: const InputDecoration(
            labelText: 'Ou chez…',
            prefixIcon: Icon(Icons.person_outline),
          ),
          items: [
            const DropdownMenuItem(
              value: '__me__',
              child: Text('Chez moi'),
            ),
            ..._friends.map(
              (f) => DropdownMenuItem(
                value: f['profile_id'] as String,
                child: Text('Chez ${f['username']}'),
              ),
            ),
            const DropdownMenuItem(
              value: '__manual__',
              child: Text('Autre nom (hors app)'),
            ),
          ],
          onChanged: widget.readOnly
              ? null
              : (v) {
                  if (v == '__me__') {
                    _selectMe();
                  } else if (v == '__manual__') {
                    setState(() => _useManual = true);
                    _emitManual();
                  } else {
                    final f = _friends.firstWhere(
                      (x) => x['profile_id'] == v,
                      orElse: () => {},
                    );
                    _selectFriend(
                      v,
                      f['username'] as String? ?? 'Ami',
                    );
                  }
                },
        ),
        if (_useManual) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _manualController,
            readOnly: widget.readOnly,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Ex. chez grand-mère',
            ),
            onChanged: widget.readOnly ? null : (_) => _emitManual(),
          ),
        ],
      ],
    );
  }
}
