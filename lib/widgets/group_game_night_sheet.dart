import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_group.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import '../utils/group_game_night.dart';
import '../utils/supabase_embeds.dart';
import 'bgg_network_image.dart';

Future<void> showGroupGameNightSheet(
  BuildContext context, {
  required CollectionGroup group,
  required int memberCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroupGameNightSheet(group: group, memberCount: memberCount),
  );
}

class _GroupGameNightSheet extends StatefulWidget {
  final CollectionGroup group;
  final int memberCount;

  const _GroupGameNightSheet({
    required this.group,
    required this.memberCount,
  });

  @override
  State<_GroupGameNightSheet> createState() => _GroupGameNightSheetState();
}

class _GroupGameNightSheetState extends State<_GroupGameNightSheet> {
  List<GameNightPick>? _picks;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Supabase.instance.client
        .from('collection_items')
        .select(SupabaseEmbeds.collectionItem)
        .eq('group_id', widget.group.id)
        .eq('category', CollectionCategory.boardgame.dbValue)
        .eq('is_wishlist', false);
    final items = (rows as List)
        .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
        .where(isActiveCollectionItem)
        .where((i) => !i.isExpansion)
        .toList();
    if (!mounted) return;
    setState(() {
      _picks = pickGamesForGameNight(
        items,
        playerCount: widget.memberCount,
      );
      _loading = false;
    });
  }

  Future<void> _share() async {
    final picks = _picks;
    if (picks == null || picks.isEmpty) return;
    final text = formatGameNightShareText(
      groupName: widget.group.name,
      playerCount: widget.memberCount,
      picks: picks,
      inviteLink: 'https://collectingo.app/groups/${widget.group.id}',
    );
    await Share.share(text, subject: 'On joue à quoi ce soir ?');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'On joue à quoi ce soir ?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${widget.group.name} · ${widget.memberCount} '
              'joueur${widget.memberCount > 1 ? 's' : ''}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_picks == null || _picks!.isEmpty)
              const Text('Aucun jeu de société du groupe ne convient à ce nombre de joueurs.')
            else
              ...[
                for (final p in _picks!)
                  ListTile(
                    leading: p.item.imageUrl != null
                        ? BggNetworkImage(
                            url: p.item.imageUrl!,
                            width: 48,
                            height: 48,
                          )
                        : const Icon(Icons.extension),
                    title: Text(p.item.title),
                    subtitle: Text(
                      [
                        if (p.item.minPlayers != null && p.item.maxPlayers != null)
                          '${p.item.minPlayers}–${p.item.maxPlayers} j.',
                        if (p.item.playingTime != null) '${p.item.playingTime} min',
                      ].join(' · '),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('game_night_share'),
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Partager la sélection'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final text = formatGameNightShareText(
                      groupName: widget.group.name,
                      playerCount: widget.memberCount,
                      picks: _picks!,
                    );
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Texte copié')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copier le résumé'),
                ),
              ],
          ],
        ),
      ),
    );
  }
}
