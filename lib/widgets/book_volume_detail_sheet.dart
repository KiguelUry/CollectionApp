import 'package:flutter/material.dart';

import '../../constants/book_accent.dart';
import '../../models/book_series.dart';
import '../../models/book_volume.dart';
import '../../services/book_series_service.dart';
import '../../widgets/collection_cover_image.dart';
import '../../widgets/cover_preview_sheet.dart';

/// Feuille détail tome : titre, description, image, switches Possédé/Lu.
Future<void> showBookVolumeDetailSheet(
  BuildContext context, {
  required BookSeries series,
  required BookVolumeSlot slot,
  required BookSeriesService service,
  VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _BookVolumeDetailSheet(
      series: series,
      slot: slot,
      service: service,
      onChanged: onChanged,
    ),
  );
}

class _BookVolumeDetailSheet extends StatefulWidget {
  final BookSeries series;
  final BookVolumeSlot slot;
  final BookSeriesService service;
  final VoidCallback? onChanged;

  const _BookVolumeDetailSheet({
    required this.series,
    required this.slot,
    required this.service,
    this.onChanged,
  });

  @override
  State<_BookVolumeDetailSheet> createState() => _BookVolumeDetailSheetState();
}

class _BookVolumeDetailSheetState extends State<_BookVolumeDetailSheet> {
  bool _busy = false;
  late bool _owned;
  late bool _read;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
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
      widget.onChanged?.call();
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

  Future<void> _setRead(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.toggleVolumeRead(
        slot: widget.slot,
        read: value,
      );
      _read = value;
      widget.onChanged?.call();
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
    final vol = widget.slot.volume;
    final cover = vol.coverUrl;
    final desc = vol.description;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vol.displayTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                widget.series.name,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (vol.isManualPlaceholder) ...[
                const SizedBox(height: 6),
                Text(
                  'Tome anticipé — sera fusionné si le catalogue le reconnaît.',
                  style: TextStyle(
                    fontSize: 12,
                    color: BookAccent.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (vol.isHorsSerie) ...[
                const SizedBox(height: 6),
                Chip(
                  label: const Text('Hors-série'),
                  backgroundColor: BookAccent.surface,
                  labelStyle: TextStyle(color: BookAccent.primary),
                ),
              ],
              const SizedBox(height: 16),
              if (cover != null && cover.isNotEmpty)
                Center(
                  child: GestureDetector(
                    onTap: () => showCoverPreview(
                      context,
                      imageUrl: cover,
                      title: vol.displayTitle,
                      bookCover: true,
                    ),
                    child: CollectionCoverImage(
                      key: ValueKey(cover),
                      url: cover,
                      width: 140,
                      height: 210,
                      bookCover: true,
                      largeSource: true,
                    ),
                  ),
                ),
              if (desc != null) ...[
                const SizedBox(height: 16),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(Icons.home_rounded, color: BookAccent.primary),
                title: const Text('Possédé'),
                subtitle: const Text('Dans ta collection'),
                value: _owned,
                onChanged: _busy ? null : _setOwned,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary:
                    Icon(Icons.visibility_rounded, color: Colors.amber.shade800),
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
      ),
    );
  }
}
