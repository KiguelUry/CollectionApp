import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Demande le numéro de tome (ex. ajout Walking Dead tome 12).
Future<double?> showVolumeNumberDialog(
  BuildContext context, {
  required String seriesName,
  double? suggested,
  int? maxHint,
}) {
  return showDialog<double>(
    context: context,
    builder: (ctx) => _VolumeNumberDialog(
      seriesName: seriesName,
      suggested: suggested,
      maxHint: maxHint,
    ),
  );
}

class _VolumeNumberDialog extends StatefulWidget {
  final String seriesName;
  final double? suggested;
  final int? maxHint;

  const _VolumeNumberDialog({
    required this.seriesName,
    this.suggested,
    this.maxHint,
  });

  @override
  State<_VolumeNumberDialog> createState() => _VolumeNumberDialogState();
}

class _VolumeNumberDialogState extends State<_VolumeNumberDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final s = widget.suggested;
    _controller = TextEditingController(
      text: s != null
          ? (s == s.roundToDouble() ? s.toInt().toString() : s.toString())
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro de tome invalide')),
      );
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quel tome ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Série « ${widget.seriesName} »',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          if (widget.maxHint != null) ...[
            const SizedBox(height: 4),
            Text(
              'La série compte ${widget.maxHint} tomes au total.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Numéro du tome',
              hintText: '1',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Valider')),
      ],
    );
  }
}
