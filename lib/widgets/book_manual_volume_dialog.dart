import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../constants/book_accent.dart';
import '../models/book_series.dart';
import '../services/book_custom_cover_service.dart';
import '../services/book_series_service.dart';

/// Dialogue d'ajout manuel : numéro optionnel, titre, image hors-série.
Future<bool?> showBookManualVolumeDialog(
  BuildContext context, {
  required BookSeries series,
  required BookSeriesService service,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _BookManualVolumeDialog(
      series: series,
      service: service,
    ),
  );
}

class _BookManualVolumeDialog extends StatefulWidget {
  final BookSeries series;
  final BookSeriesService service;

  const _BookManualVolumeDialog({
    required this.series,
    required this.service,
  });

  @override
  State<_BookManualVolumeDialog> createState() => _BookManualVolumeDialogState();
}

class _BookManualVolumeDialogState extends State<_BookManualVolumeDialog> {
  final _numberCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _coverService = BookCustomCoverService();
  bool _owned = true;
  bool _read = false;
  bool _busy = false;
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _numberCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final bytes = await _coverService.pickImageBytes();
    if (bytes != null && mounted) setState(() => _imageBytes = bytes);
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique un titre')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final isHorsSerie = _numberCtrl.text.trim().isEmpty;
      String? coverUrl;
      if (isHorsSerie && _imageBytes != null) {
        coverUrl = await _coverService.uploadCover(
          seriesId: widget.series.id,
          bytes: _imageBytes!,
        );
      }

      await widget.service.createManualVolume(
        series: widget.series,
        volumeNumberText: _numberCtrl.text.trim().isEmpty
            ? null
            : _numberCtrl.text.trim(),
        title: title,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        coverUrl: coverUrl,
        owned: _owned,
        read: _read,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHorsSerie = _numberCtrl.text.trim().isEmpty;

    return AlertDialog(
      title: const Text('Ajouter un tome'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _numberCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Numéro de tome (optionnel)',
                hintText: 'Vide = hors-série',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titre du volume',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
              ),
            ),
            if (isHorsSerie) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _imageBytes != null
                      ? 'Image sélectionnée'
                      : 'Couverture personnalisée',
                ),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Possédé'),
              value: _owned,
              activeThumbColor: BookAccent.primary,
              onChanged: _busy ? null : (v) => setState(() => _owned = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lu'),
              value: _read,
              onChanged: _busy ? null : (v) => setState(() => _read = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: BookAccent.primary,
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ajouter'),
        ),
      ],
    );
  }
}
