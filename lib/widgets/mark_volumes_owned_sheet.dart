import 'package:flutter/material.dart';

class MarkVolumesOwnedResult {
  final int from;
  final int to;
  final bool markAsRead;

  const MarkVolumesOwnedResult({
    required this.from,
    required this.to,
    this.markAsRead = false,
  });
}

/// Plage de tomes possédés (ex. 1 à 17) ou un seul tome.
Future<MarkVolumesOwnedResult?> showMarkVolumesOwnedSheet(
  BuildContext context, {
  required String seriesName,
  int? maxVolume,
}) {
  return showModalBottomSheet<MarkVolumesOwnedResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MarkVolumesOwnedSheet(
      seriesName: seriesName,
      maxVolume: maxVolume,
    ),
  );
}

class _MarkVolumesOwnedSheet extends StatefulWidget {
  final String seriesName;
  final int? maxVolume;

  const _MarkVolumesOwnedSheet({
    required this.seriesName,
    this.maxVolume,
  });

  @override
  State<_MarkVolumesOwnedSheet> createState() => _MarkVolumesOwnedSheetState();
}

class _MarkVolumesOwnedSheetState extends State<_MarkVolumesOwnedSheet> {
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '1');
  final _single = TextEditingController();
  bool _rangeMode = true;
  bool _markRead = false;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _single.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Marquer comme possédé · ${widget.seriesName}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (widget.maxVolume != null && widget.maxVolume! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Série d’environ ${widget.maxVolume} tomes',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Plage')),
              ButtonSegment(value: false, label: Text('Un tome')),
            ],
            selected: {_rangeMode},
            onSelectionChanged: (s) => setState(() => _rangeMode = s.first),
          ),
          const SizedBox(height: 12),
          if (_rangeMode)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Du tome',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('→'),
                ),
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Au tome',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            )
          else
            TextField(
              controller: _single,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Numéro du tome',
                border: OutlineInputBorder(),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Marquer aussi comme lus'),
            value: _markRead,
            onChanged: (v) => setState(() => _markRead = v),
          ),
          FilledButton(
            onPressed: () {
              int? from;
              int? to;
              if (_rangeMode) {
                from = int.tryParse(_from.text.trim());
                to = int.tryParse(_to.text.trim());
                if (from == null || to == null || from < 1 || to < 1) return;
              } else {
                final one = int.tryParse(_single.text.trim());
                if (one == null || one < 1) return;
                from = one;
                to = one;
              }
              Navigator.pop(
                context,
                MarkVolumesOwnedResult(
                  from: from,
                  to: to,
                  markAsRead: _markRead,
                ),
              );
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }
}
