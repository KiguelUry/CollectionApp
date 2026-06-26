import 'package:flutter/material.dart';

import '../../models/wildlife_taxonomy.dart';
import '../../services/wildlife_service.dart';
import '../../theme/wildlife_pokedex_theme.dart';
import '../../widgets/profile_avatar.dart';

Future<void> showWildlifeFriendsCompareSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: WildlifePokedexTheme.panel,
    showDragHandle: true,
    builder: (ctx) => const _WildlifeFriendsCompareSheet(),
  );
}

class _WildlifeFriendsCompareSheet extends StatefulWidget {
  const _WildlifeFriendsCompareSheet();

  @override
  State<_WildlifeFriendsCompareSheet> createState() =>
      _WildlifeFriendsCompareSheetState();
}

class _WildlifeFriendsCompareSheetState
    extends State<_WildlifeFriendsCompareSheet> {
  final _service = WildlifeService();
  List<WildlifeFriendStat> _stats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await _service.fetchFriendsComparison();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
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
              'Mes amis naturalistes',
              style: WildlifePokedexTheme.titleStyle(context),
            ),
            const SizedBox(height: 6),
            Text(
              'Espèces observées et répartition par règne',
              style: TextStyle(
                fontSize: 13,
                color: WildlifePokedexTheme.text.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_stats.isEmpty)
              Text(
                'Aucun ami ou collections non partagées.',
                style: TextStyle(
                  color: WildlifePokedexTheme.text.withValues(alpha: 0.7),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _stats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final s = _stats[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: WildlifePokedexTheme.tileDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ProfileAvatar(
                                avatarUrl: s.avatarUrl,
                                fallbackInitial: s.username.isNotEmpty
                                    ? s.username[0].toUpperCase()
                                    : '?',
                                radius: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.username,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: WildlifePokedexTheme.text,
                                      ),
                                    ),
                                    Text(
                                      '${s.speciesCount} espèce${s.speciesCount > 1 ? 's' : ''} · ${s.observationCount} obs.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: WildlifePokedexTheme.text
                                            .withValues(alpha: 0.65),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (s.speciesByRealm.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final e in s.speciesByRealm.entries)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(
                                      e.key.icon,
                                      size: 14,
                                      color: e.key.color,
                                    ),
                                    label: Text(
                                      '${e.key.label} ${e.value}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
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
