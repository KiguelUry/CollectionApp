import 'package:flutter/material.dart';

/// Recherche montres : pas d'API publique fiable — saisie guidée marque / modèle.
Future<Map<String, String>?> showWatchQuickSearchSheet(
  BuildContext context, {
  VoidCallback? onManualEntry,
  Color? accent,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _WatchQuickSearchSheet(
      onManualEntry: onManualEntry,
      accent: accent,
    ),
  );
}

class _WatchQuickSearchSheet extends StatefulWidget {
  final VoidCallback? onManualEntry;
  final Color? accent;

  const _WatchQuickSearchSheet({this.onManualEntry, this.accent});

  @override
  State<_WatchQuickSearchSheet> createState() => _WatchQuickSearchSheetState();
}

class _WatchQuickSearchSheetState extends State<_WatchQuickSearchSheet> {
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _refController = TextEditingController();

  static const _brands = [
    'Rolex',
    'Omega',
    'Seiko',
    'Casio',
    'Tissot',
    'Cartier',
    'TAG Heuer',
    'Breitling',
    'IWC',
    'Panerai',
    'Longines',
    'Hamilton',
    'Citizen',
    'Orient',
    'Swatch',
    'Autre',
  ];

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _refController.dispose();
    super.dispose();
  }

  void _submit() {
    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    if (brand.isEmpty && model.isEmpty) return;

    final title = [brand, model].where((s) => s.isNotEmpty).join(' ');
    Navigator.pop(context, {
      'title': title,
      'brand': brand,
      'model': model,
      if (_refController.text.trim().isNotEmpty)
        'reference': _refController.text.trim(),
      'source': 'manual_watch',
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Colors.blueGrey.shade700;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.2),
                    accent.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.watch_rounded, color: accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ajouter une montre',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Marque, modèle, référence — saisie guidée.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (text) {
                final q = text.text.toLowerCase();
                if (q.isEmpty) return _brands;
                return _brands.where((b) => b.toLowerCase().contains(q));
              },
              onSelected: (v) => _brandController.text = v == 'Autre' ? '' : v,
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                if (_brandController.text.isEmpty && controller.text.isNotEmpty) {
                  _brandController.text = controller.text;
                }
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (v) => _brandController.text = v,
                  decoration: const InputDecoration(
                    labelText: 'Marque',
                    hintText: 'Rolex, Seiko…',
                  ),
                  textCapitalization: TextCapitalization.words,
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Modèle',
                hintText: 'Submariner, Speedmaster…',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _refController,
              decoration: const InputDecoration(
                labelText: 'Référence (optionnel)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: accent),
              icon: const Icon(Icons.check),
              label: const Text('Continuer'),
            ),
            if (widget.onManualEntry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onManualEntry!();
                },
                icon: const Icon(Icons.tune),
                label: const Text('Formulaire complet'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
