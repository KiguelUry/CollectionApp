import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/bgg_service.dart';
import '../utils/debounced_runner.dart';
import 'bgg_network_image.dart';

class BggSearchDialog extends StatefulWidget {
  final Function(Map<String, String>) onGameSelected;

  const BggSearchDialog({super.key, required this.onGameSelected});

  @override
  State<BggSearchDialog> createState() => _BggSearchDialogState();
}

class _BggSearchDialogState extends State<BggSearchDialog> {
  final _controller = TextEditingController();
  final _debounce = DebouncedRunner();
  List<Map<String, String>> _results = [];
  List<Map<String, String>> _hotGames = [];
  bool _isLoading = false;
  bool _loadingHot = true;
  String? _lastQuery;
  int _searchGeneration = 0;
  BggSearchSort _sort = BggSearchSort.smart;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadHotGames();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _loadHotGames() async {
    final hot = await BggService.fetchHotBoardgames();
    if (mounted) {
      setState(() {
        _hotGames = hot;
        _loadingHot = false;
      });
    }
  }

  void _onTextChanged() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
        _lastQuery = null;
      });
      return;
    }
    _debounce.run(
      delay: const Duration(milliseconds: 400),
      action: () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    if (query.length < 1) return;

    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _lastQuery = query;
    });

    final res = await BggService.searchGames(query, sort: _sort);
    if (!mounted || generation != _searchGeneration) return;

    setState(() {
      _results = res;
      _isLoading = false;
    });
  }

  void _setSort(BggSearchSort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    final q = _controller.text.trim();
    if (q.isNotEmpty) _search(q);
  }

  bool get _showHot => _controller.text.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chercher sur BGG'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tape pour chercher (ex: 7, Catan…)',
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            if (!_showHot) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _SortChip(
                    label: 'Pertinence',
                    selected: _sort == BggSearchSort.smart,
                    onTap: () => _setSort(BggSearchSort.smart),
                  ),
                  const SizedBox(width: 6),
                  _SortChip(
                    label: 'Plus récents',
                    selected: _sort == BggSearchSort.recent,
                    onTap: () => _setSort(BggSearchSort.recent),
                  ),
                ],
              ),
            ],
            if (_lastQuery != null && _lastQuery!.isNotEmpty && !_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  _results.isEmpty
                      ? 'Aucun résultat pour « $_lastQuery »'
                      : '${_results.length} résultat(s)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            Expanded(child: _buildList()),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Sur le navigateur : pas de classement BGG ni vignettes recherche (CORS). Utilise l\'app mobile pour le détail complet.',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
            const Divider(),
            const Text(
              'Powered by BoardGameGeek',
              style: TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_showHot) {
      if (_loadingHot) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_hotGames.isEmpty) {
        return Center(
          child: Text(
            'Commence à taper pour chercher un jeu',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: [
                Icon(Icons.local_fire_department,
                    size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text(
                  'Tendances BGG',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _hotGames.length,
              itemBuilder: (context, index) =>
                  _gameTile(_hotGames[index], isHot: true),
            ),
          ),
        ],
      );
    }

    if (_results.isEmpty && !_isLoading) {
      return Center(
        child: Text(
          'Aucun jeu trouvé',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) => _gameTile(_results[index]),
    );
  }

  Widget _gameTile(Map<String, String> game, {bool isHot = false}) {
    final bggRank = game['bgg_rank'];
    final hotRank = game['hot_rank'];
    final year = game['year'];
    final imageUrl = game['image_url'];

    final subtitle = isHot
        ? [
            if (hotRank != null) 'Tendance #$hotRank',
            if (year != null && year.isNotEmpty) year,
          ].join(' · ')
        : [
            if (bggRank != null) '#$bggRank sur BGG',
            if (year != null && year.isNotEmpty) year,
          ].join(' · ');

    return ListTile(
      leading: _buildLeading(
        imageUrl: imageUrl,
        isHot: isHot,
        hotRank: hotRank,
        bggRank: bggRank,
      ),
      title: Text(game['title']!),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      onTap: () => widget.onGameSelected(game),
    );
  }

  Widget _buildLeading({
    String? imageUrl,
    required bool isHot,
    String? hotRank,
    String? bggRank,
  }) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: BggNetworkImage(url: imageUrl),
        ),
      );
    }

    if (isHot) {
      return CircleAvatar(
        backgroundColor: Colors.orange.shade50,
        child: Text(
          hotRank ?? '—',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.orange.shade800,
          ),
        ),
      );
    }

    if (bggRank != null) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.deepPurple.shade50,
        child: Text(
          '#$bggRank',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple.shade700,
          ),
        ),
      );
    }

    return const Icon(Icons.casino_outlined);
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}
