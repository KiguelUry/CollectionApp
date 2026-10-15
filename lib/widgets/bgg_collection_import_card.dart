import 'package:flutter/material.dart';

import '../services/bgg_collection_import_service.dart';

/// Import de la collection BoardGameGeek (Paramètres, réutilisable à
/// l'onboarding). L'import tourne en fond : on peut quitter l'écran.
class BggCollectionImportCard extends StatefulWidget {
  final BggCollectionImportService? service;
  final String? initialUsername;

  const BggCollectionImportCard({
    super.key,
    this.service,
    this.initialUsername,
  });

  @override
  State<BggCollectionImportCard> createState() =>
      _BggCollectionImportCardState();
}

class _BggCollectionImportCardState extends State<BggCollectionImportCard> {
  late final _controller = TextEditingController(
    text: widget.initialUsername ?? '',
  );

  BggCollectionImportService get _service =>
      widget.service ?? BggCollectionImportService.instance;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername == null) _prefill();
  }

  Future<void> _prefill() async {
    final saved = await BggCollectionImportService.savedUsername();
    if (!mounted || saved == null || _controller.text.isNotEmpty) return;
    _controller.text = saved;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    FocusScope.of(context).unfocus();
    _service.start(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<BggImportProgress>(
          valueListenable: _service.progress,
          builder: (context, p, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_download_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Importer ma collection BoardGameGeek',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Les jeux marqués « possédés » sur BGG sont ajoutés à ta '
                  'collection (les doublons sont ignorés).',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('bgg_username_field'),
                        controller: _controller,
                        enabled: !p.isRunning,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _start(),
                        decoration: const InputDecoration(
                          labelText: 'Pseudo BGG',
                          prefixIcon: Icon(Icons.person_outline),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('bgg_import_button'),
                      onPressed: p.isRunning ? null : _start,
                      child: const Text('Importer'),
                    ),
                  ],
                ),
                if (p.phase != BggImportPhase.idle) ...[
                  const SizedBox(height: 12),
                  if (p.isRunning || p.phase == BggImportPhase.done)
                    LinearProgressIndicator(
                      key: const ValueKey('bgg_import_progress'),
                      value: p.fraction,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  if (p.phase == BggImportPhase.importing && p.total > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${p.processed} / ${p.total}',
                      key: const ValueKey('bgg_import_counter'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (p.message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      p.message!,
                      key: const ValueKey('bgg_import_message'),
                      style: TextStyle(
                        fontSize: 13,
                        color: p.phase == BggImportPhase.error
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
