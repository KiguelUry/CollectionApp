import 'package:flutter/material.dart';

import '../models/book_series.dart';
import '../models/book_subcategory.dart';
import '../models/collection_item.dart';
import '../services/book_series_service.dart';

/// Rattacher un livre sans série à une série + tome.
Future<bool?> showAssignBookToSeriesSheet(
  BuildContext context, {
  required CollectionItem item,
  required BookSubcategory subcategory,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AssignBookSeriesSheet(
      item: item,
      subcategory: subcategory,
    ),
  );
}

class _AssignBookSeriesSheet extends StatefulWidget {
  final CollectionItem item;
  final BookSubcategory subcategory;

  const _AssignBookSeriesSheet({
    required this.item,
    required this.subcategory,
  });

  @override
  State<_AssignBookSeriesSheet> createState() => _AssignBookSeriesSheetState();
}

class _AssignBookSeriesSheetState extends State<_AssignBookSeriesSheet> {
  final _service = BookSeriesService();
  List<BookSeries> _series = [];
  BookSeries? _selected;
  double? _volume;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.fetchSeries(
      subcategory: widget.subcategory,
      rootsOnly: true,
    );
    if (mounted) {
      setState(() {
        _series = list;
        _loading = false;
      });
    }
  }

  Future<void> _assign() async {
    final series = _selected;
    final vol = _volume;
    if (series == null || vol == null || vol <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisis une série et un numéro de tome')),
      );
      return;
    }

    final volume = await _service.getOrCreateVolume(series.id, vol);

    await _service.linkItemToVolume(
      itemId: widget.item.id,
      seriesId: series.id,
      volumeId: volume.id,
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rattacher « ${widget.item.title} »',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_series.isEmpty)
              const Text(
                'Aucune série. Crée-en une depuis l’onglet séries.',
              )
            else ...[
              DropdownButtonFormField<BookSeries>(
                decoration: const InputDecoration(labelText: 'Série'),
                initialValue: _selected,
                items: _series
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.name),
                      ),
                    )
                    .toList(),
                onChanged: (s) => setState(() => _selected = s),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Numéro de tome',
                  hintText: 'ex: 13',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  _volume = double.tryParse(v.replaceAll(',', '.'));
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _assign,
                child: const Text('Rattacher'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
