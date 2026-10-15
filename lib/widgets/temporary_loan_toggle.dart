import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Interrupteur « C'est un prêt temporaire » + date de prêt.
class TemporaryLoanToggle extends StatelessWidget {
  final bool isLoan;
  final DateTime? loanedAt;
  final bool enabled;
  final void Function(bool isLoan, DateTime loanedAt) onChanged;

  const TemporaryLoanToggle({
    super.key,
    required this.isLoan,
    required this.loanedAt,
    required this.onChanged,
    this.enabled = true,
  });

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: loanedAt ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) onChanged(true, picked);
  }

  @override
  Widget build(BuildContext context) {
    final date = loanedAt ?? DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('temporary_loan_switch'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: Icon(Icons.handshake_outlined, color: Colors.blue.shade700),
          title: const Text('C\'est un prêt temporaire'),
          value: isLoan,
          onChanged: enabled ? (v) => onChanged(v, DateTime.now()) : null,
        ),
        if (isLoan)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('temporary_loan_date'),
              onPressed: enabled ? () => _pickDate(context) : null,
              icon: const Icon(Icons.event, size: 18),
              label: Text('Prêté le ${DateFormat('dd/MM/yyyy').format(date)}'),
            ),
          ),
      ],
    );
  }
}
