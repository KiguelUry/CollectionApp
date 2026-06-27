import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/bgg_expansion.dart';
import '../services/bgg_service.dart';
import 'bgg_network_image.dart';

Future<void> showBoardgameExpansionDetailSheet(
  BuildContext context, {
  required BggExpansion expansion,
  String? baseGameTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return _BoardgameExpansionDetailSheet(
          expansion: expansion,
          baseGameTitle: baseGameTitle,
          scrollController: scrollController,
        );
      },
    ),
  );
}

class _BoardgameExpansionDetailSheet extends StatefulWidget {
  final BggExpansion expansion;
  final String? baseGameTitle;
  final ScrollController scrollController;

  const _BoardgameExpansionDetailSheet({
    required this.expansion,
    this.baseGameTitle,
    required this.scrollController,
  });

  @override
  State<_BoardgameExpansionDetailSheet> createState() =>
      _BoardgameExpansionDetailSheetState();
}

class _BoardgameExpansionDetailSheetState
    extends State<_BoardgameExpansionDetailSheet> {
  String? _description;
  bool _loadingDescription = true;

  @override
  void initState() {
    super.initState();
    _loadDescription();
  }

  Future<void> _loadDescription() async {
    final summary = widget.expansion.summary?.trim();
    if (summary != null && summary.isNotEmpty && !summary.endsWith('…')) {
      if (mounted) {
        setState(() {
          _description = summary;
          _loadingDescription = false;
        });
      }
      return;
    }

    final full = await BggService.fetchThingDescription(widget.expansion.bggId);
    if (!mounted) return;
    setState(() {
      _description = (full != null && full.isNotEmpty)
          ? full
          : (summary != null && summary.isNotEmpty ? summary : null);
      _loadingDescription = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.expansion;
    final scheme = Theme.of(context).colorScheme;
    final bggUrl = BggService.expansionPageUrl(exp.bggId);

    return SafeArea(
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: exp.imageUrl != null && exp.imageUrl!.trim().isNotEmpty
                      ? BggNetworkImage(
                          url: exp.imageUrl!,
                          fit: BoxFit.cover,
                          boxedCover: true,
                          largeSource: true,
                        )
                      : ColoredBox(
                          color: scheme.tertiaryContainer
                              .withValues(alpha: 0.5),
                          child: Icon(
                            Icons.extension_outlined,
                            color: scheme.tertiary,
                            size: 32,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exp.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.baseGameTitle != null &&
                        widget.baseGameTitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Extension de ${widget.baseGameTitle}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                    if (exp.year != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${exp.year}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingDescription)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (_description != null && _description!.isNotEmpty)
            Text(
              _description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lora(
                fontSize: 15,
                height: 1.55,
                color: scheme.onSurface.withValues(alpha: 0.85),
              ),
            )
          else
            Text(
              'Aucune description disponible sur BGG.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (bggUrl != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(bggUrl);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Voir sur BoardGameGeek'),
            ),
          ],
        ],
      ),
    );
  }
}
