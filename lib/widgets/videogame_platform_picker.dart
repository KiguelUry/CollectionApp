import 'package:flutter/material.dart';

import '../models/videogame_platform.dart';
import '../utils/videogame_metadata.dart';

/// Sélection des plateformes possédées pour un jeu vidéo.
Future<List<VideogamePlatform>?> showVideogamePlatformPicker(
  BuildContext context, {
  List<VideogamePlatform> initial = const [],
  List<VideogamePlatform> suggested = const [],
  bool allowSkip = true,
}) async {
  final selected = <VideogamePlatform>{...initial};
  for (final p in suggested) {
    selected.add(p);
  }

  return showModalBottomSheet<List<VideogamePlatform>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sur quelle(s) plateforme(s) ?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tu pourras filtrer ta collection par console ensuite.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in VideogamePlatform.values)
                            FilterChip(
                              avatar: Icon(p.icon, size: 18),
                              label: Text(p.label),
                              selected: selected.contains(p),
                              onSelected: (on) {
                                setState(() {
                                  if (on) {
                                    selected.add(p);
                                  } else {
                                    selected.remove(p);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                              context,
                              selected.toList()
                                ..sort((a, b) => a.label.compareTo(b.label)),
                            ),
                    child: const Text('Valider'),
                  ),
                  if (allowSkip)
                    TextButton(
                      onPressed: () => Navigator.pop(context, <VideogamePlatform>[]),
                      child: const Text('Passer'),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Plateformes, progression et statut de jeu — fiche détail.
class VideogameDetailSection extends StatelessWidget {
  final Map<String, dynamic>? metadata;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;

  const VideogameDetailSection({
    super.key,
    required this.metadata,
    required this.readOnly,
    required this.onMetadataChanged,
  });

  List<VideogamePlatform> get _selected {
    return videogamePlatformIdsFromMetadata(metadata)
        .map(VideogamePlatform.fromId)
        .whereType<VideogamePlatform>()
        .toList();
  }

  void _update(Map<String, dynamic> Function(Map<String, dynamic> meta) fn) {
    final next = fn(Map<String, dynamic>.from(metadata ?? {}));
    onMetadataChanged(next);
  }

  Future<void> _pickPlatforms(BuildContext context) async {
    final picked = await showVideogamePlatformPicker(
      context,
      initial: _selected,
      allowSkip: false,
    );
    if (picked == null) return;
    onMetadataChanged(metadataWithPlatforms(metadata, picked));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = Colors.green.shade700;
    final completion = videogameCompletionPercent(metadata);
    final status = videogamePlayStatus(metadata);
    final community = videogameCommunityRating(metadata);
    final year = metadata?['year']?.toString();
    final summary = metadata?['summary']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (year != null && year.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Sortie : $year',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        if (community != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.public, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Note communauté : ${community.toStringAsFixed(1)} / 5',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Plateformes',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
            if (!readOnly)
              TextButton.icon(
                onPressed: () => _pickPlatforms(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifier'),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _selected.isEmpty
              ? [
                  Text(
                    'Aucune plateforme — ajoute-en pour filtrer ta collection.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ]
              : _selected
                  .map(
                    (p) => Chip(
                      avatar: Icon(p.icon, size: 16),
                      label: Text(p.label, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Progression',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: (completion ?? 0).toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${completion ?? 0} %',
                onChanged: readOnly
                    ? null
                    : (v) => _update((m) {
                          m['completion_percent'] = v.round();
                          return m;
                        }),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${completion ?? 0} %',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: VideogamePlayStatus.values.map((s) {
            return ChoiceChip(
              label: Text(s.label, style: const TextStyle(fontSize: 12)),
              selected: status == s,
              onSelected: readOnly
                  ? null
                  : (_) => _update((m) {
                        m['play_status'] = s.id;
                        return m;
                      }),
            );
          }).toList(),
        ),
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Résumé',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
