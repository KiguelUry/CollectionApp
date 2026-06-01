import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/book_catalog_service.dart';

/// Scan ISBN / EAN ou saisie manuelle (mobile). Retourne le code nettoyé.
Future<String?> showIsbnScanSheet(
  BuildContext context, {
  String title = 'Scanner un code-barres',
  String? hint,
  /// Si false, valide sans interroger le catalogue livres (ex. vinyle).
  bool validateBookLookup = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _IsbnScanSheet(
      title: title,
      hint: hint,
      validateBookLookup: validateBookLookup,
    ),
  );
}

class _IsbnScanSheet extends StatefulWidget {
  final String title;
  final String? hint;
  final bool validateBookLookup;

  const _IsbnScanSheet({
    required this.title,
    this.hint,
    required this.validateBookLookup,
  });

  @override
  State<_IsbnScanSheet> createState() => _IsbnScanSheetState();
}

class _IsbnScanSheetState extends State<_IsbnScanSheet> {
  final _manualController = TextEditingController();
  bool _handled = false;

  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _submit(String raw) {
    if (_handled) return;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length < 10) return;
    _handled = true;
    Navigator.pop(context, cleaned);
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
              widget.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.hint ??
                  (_canScan
                      ? 'Cadre le code ISBN/EAN (ou saisis-le ci-dessous).'
                      : 'Sur PC, saisis le code manuellement.'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (_canScan) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 220,
                  child: MobileScanner(
                    onDetect: (capture) {
                      for (final code in capture.barcodes) {
                        final raw = code.rawValue;
                        if (raw != null && raw.isNotEmpty) {
                          _submit(raw);
                          break;
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _manualController,
              decoration: const InputDecoration(
                labelText: 'ISBN / EAN',
                hintText: '9782070368228',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onSubmitted: _submit,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final isbn = _manualController.text.trim();
                if (isbn.isEmpty) return;
                if (widget.validateBookLookup) {
                  final book = await BookCatalogService.lookupByIsbn(isbn);
                  if (!context.mounted) return;
                  if (book == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Code introuvable (Open Library + Google Books)',
                        ),
                      ),
                    );
                    return;
                  }
                }
                _submit(isbn);
              },
              icon: const Icon(Icons.search),
              label: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }
}
