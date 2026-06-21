import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../models/book_series.dart';
import '../models/book_volume.dart';
import '../services/book_series_service.dart';

/// Feuille pour basculer Possédé × Lu sur un tome.
Future<void> showBookVolumeStatusSheet(
  BuildContext context, {
  required BookSeries series,
  required BookVolumeSlot slot,
  required BookSeriesService service,
  VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _BookVolumeStatusSheet(
      series: series,
      slot: slot,
      service: service,
      onChanged: onChanged,
    ),
  );
}

class _BookVolumeStatusSheet extends StatefulWidget {
  final BookSeries series;
  final BookVolumeSlot slot;
  final BookSeriesService service;
  final VoidCallback? onChanged;

  const _BookVolumeStatusSheet({
    required this.series,
    required this.slot,
    required this.service,
    this.onChanged,
  });

  @override
  State<_BookVolumeStatusSheet> createState() => _BookVolumeStatusSheetState();
}

class _BookVolumeStatusSheetState extends State<_BookVolumeStatusSheet> {
  bool _busy = false;
  late bool _owned;
  late bool _read;

  @override
  void initState() {
    super.initState();
    _syncFromSlot();
  }

  void _syncFromSlot() {
    final item = widget.slot.item;
    _owned = item != null && !item.isWishlist;
    _read = (item?.isRead ?? false) || widget.slot.volume.isRead;
  }

  Future<void> _setOwned(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.toggleVolumeOwned(
        series: widget.series,
        slot: widget.slot,
        owned: value,
      );
      _owned = value;
      if (!value && _read) {
        await widget.service.setVolumeReadFlag(widget.slot.volume.id, true);
      }
      if (mounted) setState(() => _busy = false);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _setRead(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.toggleVolumeRead(
        slot: widget.slot,
        read: value,
      );
      _read = value;
      if (mounted) setState(() => _busy = false);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.slot.volume.displayNumber;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tome $n',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              widget.series.name,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              secondary: Icon(Icons.home_rounded, color: BookAccent.primary),
              title: const Text('Possédé'),
              subtitle: const Text('Dans ta collection'),
              value: _owned,
              onChanged: _busy ? null : _setOwned,
            ),
            SwitchListTile(
              secondary: Icon(Icons.visibility_rounded, color: Colors.amber.shade800),
              title: const Text('Lu'),
              subtitle: const Text('Lu ou emprunté, même sans possession'),
              value: _read,
              onChanged: _busy ? null : _setRead,
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
