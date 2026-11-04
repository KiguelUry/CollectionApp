import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/friend_service.dart';
import 'profile_avatar.dart';

/// Interrupteur « C'est un prêt temporaire » + date + à qui.
/// Pas de liste de noms sous le champ : icône amis à droite de la saisie.
class TemporaryLoanToggle extends StatefulWidget {
  final bool isLoan;
  final DateTime? loanedAt;
  final String? borrowerName;
  final bool enabled;
  /// Si true et prêt actif : pas de switch (le parent a déjà « Rendre »).
  final bool hideSwitchWhenActive;
  /// [borrowerName] fourni au moment de l'activation (après pop-up).
  final void Function(bool isLoan, DateTime loanedAt, {String? borrowerName})
      onChanged;
  final ValueChanged<String>? onBorrowerChanged;

  const TemporaryLoanToggle({
    super.key,
    required this.isLoan,
    required this.loanedAt,
    required this.onChanged,
    this.borrowerName,
    this.onBorrowerChanged,
    this.enabled = true,
    this.hideSwitchWhenActive = false,
  });

  @override
  State<TemporaryLoanToggle> createState() => _TemporaryLoanToggleState();
}

class _TemporaryLoanToggleState extends State<TemporaryLoanToggle> {
  late final TextEditingController _who;
  final _whoFocus = FocusNode();
  List<Map<String, dynamic>> _friends = const [];

  @override
  void initState() {
    super.initState();
    _who = TextEditingController(text: widget.borrowerName ?? '');
    _loadFriends();
  }

  @override
  void didUpdateWidget(covariant TemporaryLoanToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ne pas écraser la saisie en cours (sinon focus / curseur sautent).
    if (_whoFocus.hasFocus) return;
    final next = widget.borrowerName ?? '';
    if (next != _who.text) {
      _who.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  void dispose() {
    _who.dispose();
    _whoFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final rows = await FriendService().fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = [
          for (final r in rows)
            if ((r['username']?.toString().trim() ?? '').isNotEmpty) r,
        ];
      });
    } catch (_) {}
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.loanedAt ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) widget.onChanged(true, picked);
  }

  Future<String?> _pickFriendName() async {
    if (_friends.isEmpty) {
      await _loadFriends();
    }
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        if (_friends.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun ami dans ton carnet.'),
            ),
          );
        }
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Choisir un ami',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              for (final friend in _friends)
                ListTile(
                  leading: ProfileAvatar(
                    avatarUrl: friend['avatar_url'] as String?,
                    accentColorHex: friend['accent_color'] as String?,
                    fallbackInitial: friend['username'] as String? ?? '?',
                    radius: 18,
                  ),
                  title: Text(friend['username'] as String),
                  onTap: () =>
                      Navigator.pop(ctx, friend['username'] as String),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFriendIntoField() async {
    final chosen = await _pickFriendName();
    if (chosen == null || !mounted) return;
    _who.text = chosen;
    widget.onBorrowerChanged?.call(chosen.trim());
  }

  /// Pop-up au moment où on coche le prêt : désigner l'emprunteur.
  Future<String?> _promptBorrower() async {
    final ctrl = TextEditingController(text: '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('À qui le prêtes-tu ?'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Prêté à',
              hintText: 'Ami ou nom libre',
              prefixIcon: const Icon(Icons.person_outline),
              suffixIcon: IconButton(
                tooltip: 'Choisir un ami',
                onPressed: () async {
                  final chosen = await _pickFriendName();
                  if (chosen != null) ctrl.text = chosen;
                },
                icon: Icon(Icons.group_outlined, color: Colors.blue.shade700),
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              final t = v.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(ctx, t);
              },
              child: const Text('Prêter'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return name;
  }

  Future<void> _onSwitch(bool enable) async {
    if (!enable) {
      widget.onChanged(false, DateTime.now());
      return;
    }
    final name = await _promptBorrower();
    if (name == null || !mounted) return;
    _who.text = name;
    widget.onChanged(true, DateTime.now(), borrowerName: name);
    widget.onBorrowerChanged?.call(name);
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.loanedAt ?? DateTime.now();
    final showSwitch =
        !(widget.hideSwitchWhenActive && widget.isLoan);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSwitch)
          SwitchListTile(
            key: const ValueKey('temporary_loan_switch'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary:
                Icon(Icons.handshake_outlined, color: Colors.blue.shade700),
            title: const Text('C\'est un prêt temporaire'),
            value: widget.isLoan,
            onChanged: widget.enabled ? _onSwitch : null,
          ),
        if (widget.isLoan) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('temporary_loan_date'),
              onPressed: widget.enabled ? () => _pickDate(context) : null,
              icon: const Icon(Icons.event, size: 18),
              label: Text('Prêté le ${DateFormat('dd/MM/yyyy').format(date)}'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('temporary_loan_who'),
            controller: _who,
            focusNode: _whoFocus,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: 'Prêté à',
              hintText: 'Ami ou nom libre',
              isDense: true,
              prefixIcon: const Icon(Icons.person_outline),
              suffixIcon: IconButton(
                tooltip: 'Choisir un ami',
                onPressed: widget.enabled ? _pickFriendIntoField : null,
                icon: Icon(Icons.group_outlined, color: Colors.blue.shade700),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => widget.onBorrowerChanged?.call(v.trim()),
          ),
        ],
      ],
    );
  }
}
