import 'package:flutter/material.dart';

import '../models/collection_item.dart';

/// Choix du jeu de la collection auquel rattacher une partie orpheline.
/// Retourne le [CollectionItem] choisi via `Navigator.pop`.
class OrphanAttachSheet extends StatefulWidget {
  final String orphanTitle;
  final List<CollectionItem> candidates;

  const OrphanAttachSheet({
    super.key,
    required this.orphanTitle,
    required this.candidates,
  });

  @override
  State<OrphanAttachSheet> createState() => _OrphanAttachSheetState();
}

class _OrphanAttachSheetState extends State<OrphanAttachSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((i) => i.title.toLowerCase().contains(q))
            .toList();
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Rattacher « ${widget.orphanTitle} »',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Choisis le jeu de ta collection qui recevra cette partie.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Rechercher un jeu',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final item = visible[i];
                  return ListTile(
                    leading: const Icon(Icons.casino_outlined),
                    title: Text(item.title),
                    onTap: () => Navigator.pop(context, item),
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
