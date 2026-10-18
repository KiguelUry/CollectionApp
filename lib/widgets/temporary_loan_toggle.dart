import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/friend_service.dart';
import 'profile_avatar.dart';

/// Interrupteur « C'est un prêt temporaire » + date + à qui.
class TemporaryLoanToggle extends StatefulWidget {
  final bool isLoan;
  final DateTime? loanedAt;
  final String? borrowerName;
  final bool enabled;
  final void Function(bool isLoan, DateTime loanedAt) onChanged;
  final ValueChanged<String>? onBorrowerChanged;

  const TemporaryLoanToggle({
    super.key,
    required this.isLoan,
    required this.loanedAt,
    required this.onChanged,
    this.borrowerName,
    this.onBorrowerChanged,
    this.enabled = true,
  });

  @override
  State<TemporaryLoanToggle> createState() => _TemporaryLoanToggleState();
}

class _TemporaryLoanToggleState extends State<TemporaryLoanToggle> {
  late final TextEditingController _who;
  List<Map<String, dynamic>> _friends = const [];

  @override
  void initState() {
    super.initState();
    _who = TextEditingController(text: widget.borrowerName ?? '');
    if (widget.isLoan) _loadFriends();
  }

  @override
  void didUpdateWidget(covariant TemporaryLoanToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.borrowerName ?? '';
    if (next != _who.text && next.isNotEmpty) _who.text = next;
    if (widget.isLoan && !oldWidget.isLoan) _loadFriends();
  }

  @override
  void dispose() {
    _who.dispose();
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

  void _setBorrower(String name) {
    _who.text = name;
    widget.onBorrowerChanged?.call(name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.loanedAt ?? DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('temporary_loan_switch'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: Icon(Icons.handshake_outlined, color: Colors.blue.shade700),
          title: const Text('C\'est un prêt temporaire'),
          value: widget.isLoan,
          onChanged: widget.enabled
              ? (v) => widget.onChanged(v, DateTime.now())
              : null,
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
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Prêté à',
              hintText: 'Ami, membre ou nom libre',
              isDense: true,
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => widget.onBorrowerChanged?.call(v.trim()),
          ),
          if (_friends.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final friend in _friends.take(12))
                  FilterChip(
                    avatar: ProfileAvatar(
                      avatarUrl: friend['avatar_url'] as String?,
                      accentColorHex: friend['accent_color'] as String?,
                      fallbackInitial: friend['username'] as String? ?? '?',
                      radius: 12,
                    ),
                    label: Text(friend['username'] as String),
                    selected: _who.text.trim().toLowerCase() ==
                        (friend['username'] as String).toLowerCase(),
                    onSelected: widget.enabled
                        ? (_) => _setBorrower(friend['username'] as String)
                        : null,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
