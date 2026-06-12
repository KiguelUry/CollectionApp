import 'package:flutter/material.dart';

import '../utils/debounced_runner.dart';
import 'bgg_network_image.dart';
import 'ui/empty_state.dart';

typedef CatalogSearchFn = Future<List<Map<String, String>>> Function(String query);

/// Feuille de recherche catalogue réutilisable (films, jeux, Lego…).
Future<Map<String, String>?> showCatalogSearchSheet(
  BuildContext context, {
  required String title,
  required String hint,
  required CatalogSearchFn search,
  String? apiHint,
  VoidCallback? onManualEntry,
  Color? accent,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _CatalogSearchSheet(
      title: title,
      hint: hint,
      search: search,
      apiHint: apiHint,
      onManualEntry: onManualEntry,
      accent: accent,
    ),
  );
}

class _CatalogSearchSheet extends StatefulWidget {
  final String title;
  final String hint;
  final CatalogSearchFn search;
  final String? apiHint;
  final VoidCallback? onManualEntry;
  final Color? accent;

  const _CatalogSearchSheet({
    required this.title,
    required this.hint,
    required this.search,
    this.apiHint,
    this.onManualEntry,
    this.accent,
  });

  @override
  State<_CatalogSearchSheet> createState() => _CatalogSearchSheetState();
}

class _CatalogSearchSheetState extends State<_CatalogSearchSheet> {
  final _controller = TextEditingController();
  final _debounce = DebouncedRunner();
  List<Map<String, String>> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    final q = _controller.text.trim();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 450),
      action: _runSearch,
    );
  }

  Future<void> _runSearch() async {
    final q = _controller.text.trim();
    if (q.length < 2) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    final list = await widget.search(q);
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.18),
                    accent.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search_rounded, color: accent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.apiHint != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.apiHint!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: Icon(Icons.search, color: accent),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: accent, width: 2),
                  ),
                ),
              ),
            ),
            if (widget.onManualEntry != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onManualEntry!();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Saisir à la main'),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !_searched
                      ? Center(
                          child: Text(
                            'Tape au moins 2 caractères',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : _results.isEmpty
                          ? const EmptyState(
                              icon: Icons.search_off,
                              title: 'Aucun résultat',
                              message: 'Essaie un autre terme ou saisis à la main.',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _results.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final r = _results[i];
                                final img = r['image_url'];
                                final sub = [
                                  r['year'],
                                  r['platform'],
                                  if (r['set_number']?.isNotEmpty == true)
                                    'Set ${r['set_number']}',
                                  if (r['media_kind'] == 'movie')
                                    'Film',
                                ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

                                return ListTile(
                                  leading: img != null && img.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: BggNetworkImage(
                                            url: img,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Icon(Icons.image_outlined),
                                  title: Text(r['title'] ?? ''),
                                  subtitle: sub.isNotEmpty ? Text(sub) : null,
                                  onTap: () => Navigator.pop(context, r),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
