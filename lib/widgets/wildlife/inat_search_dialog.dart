import 'package:flutter/material.dart';

import '../../services/inaturalist_service.dart';

/// Dialogue iNaturalist — défilement adapté au clavier virtuel.
class WildlifeINatSearchDialog extends StatefulWidget {
  final String? initialQuery;
  final String title;

  const WildlifeINatSearchDialog({
    super.key,
    this.initialQuery,
    this.title = 'Chercher sur iNaturalist',
  });

  @override
  State<WildlifeINatSearchDialog> createState() =>
      _WildlifeINatSearchDialogState();
}

class _WildlifeINatSearchDialogState extends State<WildlifeINatSearchDialog> {
  late final TextEditingController _controller;
  List<WildlifeTaxonHit> _hits = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    if ((widget.initialQuery ?? '').trim().length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final hits = await INaturalistService.searchSpecies(_controller.text);
    if (mounted) {
      setState(() {
        _hits = hits;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxH = MediaQuery.sizeOf(context).height - viewInsets.vertical - 140;

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH.clamp(200, 520)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Léopard, mésange, papillon…',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              if (_searching)
                const LinearProgressIndicator()
              else
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    itemCount: _hits.length,
                    itemBuilder: (context, i) {
                      final h = _hits[i];
                      return ListTile(
                        leading: h.imageUrl != null
                            ? Image.network(
                                h.imageUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.pets),
                        title: Text(h.displayTitle),
                        subtitle: Text(h.name, maxLines: 1),
                        onTap: () => Navigator.pop(context, h),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}
