import 'package:flutter/material.dart';

import '../models/category_metadata.dart';
import '../models/media_format_ui.dart';
import '../services/media_catalog_service.dart';
import '../utils/debounced_runner.dart';
import 'bgg_network_image.dart';
import 'isbn_scan_sheet.dart';
import 'ui/empty_state.dart';

Future<Map<String, String>?> showMediaQuickSearchSheet(
  BuildContext context, {
  MediaFormat initialFormat = MediaFormat.vinyl,
  VoidCallback? onManualEntry,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _MediaQuickSearchSheet(
      initialFormat: initialFormat,
      onManualEntry: onManualEntry,
    ),
  );
}

class _MediaQuickSearchSheet extends StatefulWidget {
  final MediaFormat initialFormat;
  final VoidCallback? onManualEntry;

  const _MediaQuickSearchSheet({
    required this.initialFormat,
    this.onManualEntry,
  });

  @override
  State<_MediaQuickSearchSheet> createState() => _MediaQuickSearchSheetState();
}

class _MediaQuickSearchSheetState extends State<_MediaQuickSearchSheet> {
  late MediaFormat _format = widget.initialFormat;
  final _artistController = TextEditingController();
  final _titleController = TextEditingController();
  final _debounce = DebouncedRunner();
  List<Map<String, String>> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _artistController.addListener(_scheduleSearch);
    _titleController.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    final artist = _artistController.text.trim();
    final title = _titleController.text.trim();
    if (artist.length < 2 && title.length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 450),
      action: _search,
    );
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final res = await MediaCatalogService.searchReleasesAdvanced(
        artist: _artistController.text,
        title: _titleController.text,
        format: _format,
      );
      if (!mounted) return;
      setState(() {
        _results = res;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _scanBarcode() async {
    final code = await showIsbnScanSheet(
      context,
      title: 'Scanner le code-barres',
      hint: 'EAN / UPC de l\'album',
      validateBookLookup: false,
    );
    if (code == null || !mounted) return;

    setState(() => _loading = true);
    final album = await MediaCatalogService.lookupByBarcode(
      code,
      format: _format,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (album != null) {
      Navigator.pop(context, album);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun album pour ce code')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Trouver un album',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final f in MediaFormat.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.label, style: const TextStyle(fontSize: 12)),
                      selected: _format == f,
                      onSelected: (_) => setState(() => _format = f),
                      avatar: Icon(f.icon, size: 16, color: f.color),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(
              onPressed: _loading ? null : _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scanner un code-barres'),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _artistController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Artiste',
                prefixIcon: Icon(Icons.person_outline),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _titleController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Titre d\'album',
                prefixIcon: const Icon(Icons.album_outlined),
                isDense: true,
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search_rounded),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text(
              MediaCatalogService.catalogLabel(format: _format),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
          if (widget.onManualEntry != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onManualEntry!();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Saisie manuelle'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return EmptyState(
        icon: Icons.album_outlined,
        title: 'Artiste et/ou titre',
        message: 'Renseigne au moins 2 caractères dans un des champs, ou scanne.',
        iconColor: _format.color,
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: Icons.music_off_outlined,
        title: 'Aucun album',
        message: 'Essaie un autre titre ou le scan.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final a = _results[i];
        final img = a['image_url'];
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.pop(context, a),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: img != null && img.isNotEmpty
                        ? SizedBox(
                            width: 52,
                            height: 52,
                            child: BggNetworkImage(url: img),
                          )
                        : Container(
                            width: 52,
                            height: 52,
                            color: _format.color.withValues(alpha: 0.12),
                            child: Icon(Icons.album, color: _format.color),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a['title'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            if ((a['artist'] ?? '').isNotEmpty) a['artist'],
                            if ((a['year'] ?? '').isNotEmpty) a['year'],
                          ].whereType<String>().join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.add_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
