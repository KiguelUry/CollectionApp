import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/book_catalog_service.dart';

const _kRafalePref = 'isbn_scan_rafale_mode';

/// Résultat d'un scan unitaire ou session rafale.
class IsbnScanOutcome {
  final String? singleIsbn;
  final int batchAddedCount;
  final bool refreshNeeded;

  const IsbnScanOutcome({
    this.singleIsbn,
    this.batchAddedCount = 0,
    this.refreshNeeded = false,
  });
}

/// Entrée d'historique pour le Mode Rafale.
class IsbnRafaleHistoryEntry {
  final String isbn;
  final String label;
  final String? coverUrl;
  final String? itemId;
  final Future<void> Function()? onUndo;

  const IsbnRafaleHistoryEntry({
    required this.isbn,
    required this.label,
    this.coverUrl,
    this.itemId,
    this.onUndo,
  });
}

/// Callback Mode Rafale : résout + possède le tome en arrière-plan.
typedef IsbnRafaleHandler = Future<IsbnRafaleHistoryEntry?> Function(
  String isbn,
);

/// Scan ISBN / EAN ou saisie manuelle.
/// [onRafaleScan] active le toggle Unitaire / ⚡ Mode Rafale.
Future<IsbnScanOutcome?> showIsbnScanSheet(
  BuildContext context, {
  String title = 'Scanner un code-barres',
  String? hint,
  /// Si false, valide sans interroger le catalogue livres (ex. vinyle).
  bool validateBookLookup = true,
  IsbnRafaleHandler? onRafaleScan,
}) {
  return showModalBottomSheet<IsbnScanOutcome>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _IsbnScanSheet(
      title: title,
      hint: hint,
      validateBookLookup: validateBookLookup,
      onRafaleScan: onRafaleScan,
    ),
  );
}

class _IsbnScanSheet extends StatefulWidget {
  final String title;
  final String? hint;
  final bool validateBookLookup;
  final IsbnRafaleHandler? onRafaleScan;

  const _IsbnScanSheet({
    required this.title,
    this.hint,
    required this.validateBookLookup,
    this.onRafaleScan,
  });

  @override
  State<_IsbnScanSheet> createState() => _IsbnScanSheetState();
}

class _IsbnScanSheetState extends State<_IsbnScanSheet> {
  final _manualController = TextEditingController();
  final _focusNode = FocusNode();
  bool _handled = false;
  bool _rafale = true;
  bool _busy = false;
  String? _lastIsbn;
  DateTime? _lastIsbnAt;
  final List<IsbnRafaleHistoryEntry> _history = [];

  bool get _canScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _rafaleEnabled => widget.onRafaleScan != null && _rafale;

  @override
  void initState() {
    super.initState();
    if (widget.onRafaleScan != null) {
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        setState(() => _rafale = prefs.getBool(_kRafalePref) ?? true);
      });
    } else {
      _rafale = false;
    }
  }

  Future<void> _persistRafale(bool value) async {
    setState(() => _rafale = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRafalePref, value);
  }

  bool _cooldownBlocks(String isbn) {
    if (_lastIsbn == isbn &&
        _lastIsbnAt != null &&
        DateTime.now().difference(_lastIsbnAt!) < const Duration(seconds: 2)) {
      return true;
    }
    return false;
  }

  void _submitUnitary(String raw) {
    if (_handled) return;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length < 10) return;
    _handled = true;
    Navigator.pop(context, IsbnScanOutcome(singleIsbn: cleaned));
  }

  Future<void> _enqueueRafale(String raw) async {
    if (_busy) return;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (cleaned.length < 10) return;
    if (_cooldownBlocks(cleaned)) return;

    _lastIsbn = cleaned;
    _lastIsbnAt = DateTime.now();
    HapticFeedback.mediumImpact();

    setState(() => _busy = true);
    try {
      final entry = await widget.onRafaleScan!(cleaned);
      if (!mounted) return;
      if (entry != null) {
        setState(() {
          _history.insert(0, entry);
          _busy = false;
        });
      } else {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ISBN $cleaned introuvable')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur scan : $e')),
      );
    }
    _manualController.clear();
    _focusNode.requestFocus();
  }

  Future<void> _undoLast() async {
    if (_history.isEmpty) return;
    final last = _history.first;
    if (last.onUndo != null) {
      await last.onUndo!();
    }
    if (!mounted) return;
    setState(() => _history.removeAt(0));
  }

  void _finish() {
    Navigator.pop(
      context,
      IsbnScanOutcome(
        batchAddedCount: _history.length,
        refreshNeeded: _history.isNotEmpty,
      ),
    );
  }

  @override
  void dispose() {
    _manualController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
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
              if (widget.onRafaleScan != null) ...[
                const SizedBox(height: 12),
                _RafaleToggle(
                  rafale: _rafale,
                  onChanged: _persistRafale,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                widget.hint ??
                    (_rafaleEnabled
                        ? (_canScan
                            ? 'Cadre les ISBN à la suite — la caméra reste ouverte.'
                            : 'Colle un ISBN et appuie sur Entrée pour enchaîner.')
                        : (_canScan
                            ? 'Cadre le code ISBN/EAN (ou saisis-le ci-dessous).'
                            : 'Sur PC, saisis le code manuellement.')),
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
                          if (raw == null || raw.isEmpty) continue;
                          if (_rafaleEnabled) {
                            _enqueueRafale(raw);
                          } else {
                            _submitUnitary(raw);
                          }
                          break;
                        }
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _manualController,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  labelText: 'ISBN / EAN',
                  hintText: '9782070368228',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  if (_rafaleEnabled) {
                    _enqueueRafale(v);
                  } else {
                    _submitUnitary(v);
                  }
                },
              ),
              if (_rafaleEnabled && _history.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Session (${_history.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _history.length,
                    itemBuilder: (ctx, i) {
                      final e = _history[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                if (e.coverUrl != null &&
                                    e.coverUrl!.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(
                                      e.coverUrl!,
                                      width: 28,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox(
                                        width: 28,
                                        height: 40,
                                        child: Icon(Icons.book, size: 18),
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(
                                    width: 28,
                                    height: 40,
                                    child: Icon(Icons.book, size: 18),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    e.label,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (i == 0)
                                  TextButton(
                                    onPressed: _undoLast,
                                    child: const Text('Annuler'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 12),
              if (_rafaleEnabled)
                FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.check),
                  label: Text(
                    _history.isEmpty
                        ? 'Terminer'
                        : 'Terminer (${_history.length} tome${_history.length > 1 ? 's' : ''} ajouté${_history.length > 1 ? 's' : ''})',
                  ),
                )
              else
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
                              'Code introuvable (Google Books + iTunes)',
                            ),
                          ),
                        );
                        return;
                      }
                    }
                    _submitUnitary(isbn);
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Valider'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RafaleToggle extends StatelessWidget {
  final bool rafale;
  final ValueChanged<bool> onChanged;

  const _RafaleToggle({required this.rafale, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: false,
          label: Text('Unitaire'),
          icon: Icon(Icons.filter_1, size: 18),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('⚡ Mode Rafale'),
          icon: Icon(Icons.bolt, size: 18),
        ),
      ],
      selected: {rafale},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer;
          }
          return null;
        }),
      ),
    );
  }
}
