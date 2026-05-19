import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/boardgame_display.dart';
import '../utils/collection_item_filters.dart';
import '../utils/collection_item_scope.dart';
import '../utils/french_plural.dart';
import '../utils/shake_pick_filters.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

/// Secoue le téléphone (mobile) ou appuie sur le bouton pour tirer un jeu au hasard.
class ShakePickScreen extends StatefulWidget {
  final CollectionCategory? category;

  const ShakePickScreen({super.key, this.category});

  @override
  State<ShakePickScreen> createState() => _ShakePickScreenState();
}

class _ShakePickScreenState extends State<ShakePickScreen>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  List<CollectionItem> _allCandidates = [];
  ShakePickFilters _filters = const ShakePickFilters();
  CollectionItem? _picked;
  bool _loading = true;
  bool _picking = false;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  int _lastShakeMs = 0;

  late AnimationController _pulseController;

  List<CollectionItem> get _filtered => _allCandidates
      .where(_filters.matches)
      .toList();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _loadCandidates();
    if (!kIsWeb) _startShakeListener();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() => _loading = true);
    try {
      final userId = CollectionItemScope.currentUserId;
      if (userId == null) {
        _allCandidates = [];
        return;
      }

      var personalQuery = CollectionItemScope.personal(
        Supabase.instance.client
            .from('collection_items')
            .select()
            .eq('is_wishlist', false)
            .eq('is_sold', false)
            .eq('is_for_sale', false),
        userId: userId,
      );

      if (widget.category != null) {
        personalQuery =
            personalQuery.eq('category', widget.category!.dbValue);
      }

      final allRows = <Map<String, dynamic>>[
        for (final r in await personalQuery as List)
          Map<String, dynamic>.from(r),
      ];

      final groupIds = await CollectionItemScope.myGroupIds(userId);
      if (groupIds.isNotEmpty) {
        var groupQuery = Supabase.instance.client
            .from('collection_items')
            .select()
            .inFilter('group_id', groupIds)
            .eq('is_wishlist', false)
            .eq('is_sold', false)
            .eq('is_for_sale', false);
        if (widget.category != null) {
          groupQuery = groupQuery.eq('category', widget.category!.dbValue);
        }
        for (final r in await groupQuery as List) {
          allRows.add(Map<String, dynamic>.from(r));
        }
      }

      final seen = <String>{};
      _allCandidates = allRows
          .where((r) => seen.add(r['id'] as String))
          .map((r) => CollectionItem.fromJson(r))
          .where(isShakePickCandidate)
          .toList();
    } catch (_) {
      _allCandidates = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _startShakeListener() {
    _accelSub = userAccelerometerEventStream().listen((event) {
      final shake = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (shake < 2.4) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastShakeMs < 1400) return;
      _lastShakeMs = now;
      _pickRandom();
    });
  }

  Future<void> _pickRandom() async {
    final pool = _filtered;
    if (_picking || pool.isEmpty) return;

    setState(() {
      _picking = true;
      _picked = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final item = pool[_random.nextInt(pool.length)];
    if (mounted) {
      setState(() {
        _picked = item;
        _picking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'À quoi on joue ce soir ?'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allCandidates.isEmpty
              ? _buildEmpty()
              : _buildContent(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Aucun jeu éligible',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoute des jeux à ta collection ou à un groupe (hors wishlist et hors vente).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final pool = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            pool.isEmpty
                ? 'Aucun jeu ne correspond aux critères'
                : '${jeuxCountLabel(pool.length)} dans le tirage',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(child: Center(child: _buildPickArea())),
        if (!kIsWeb)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Secoue le téléphone pour choisir',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.deepPurple.shade700,
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Sur le web, utilise le bouton ci-dessous',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton.icon(
            onPressed: _picking || pool.isEmpty ? null : _pickRandom,
            icon: _picking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.shuffle),
            label: Text(_picking ? 'Tirage…' : 'Tirer au sort'),
          ),
        ),
        if (_picked != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ItemDetailScreen(item: _picked!),
                ),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Voir la fiche'),
            ),
          ),
      ],
    );
  }

  Widget _buildFilters() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Critères',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _filters.playerCount,
              decoration: const InputDecoration(
                labelText: 'Nombre de joueurs',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tous'),
                ),
                for (var n = 1; n <= 20; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text('$n joueur${n > 1 ? 's' : ''}'),
                  ),
              ],
              onChanged: (v) => setState(() {
                _filters = ShakePickFilters(
                  playerCount: v,
                  duration: _filters.duration,
                );
                _picked = null;
              }),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ShakePickDuration>(
              value: _filters.duration,
              decoration: const InputDecoration(
                labelText: 'Durée de partie',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: ShakePickDuration.any,
                  child: Text('Toute durée'),
                ),
                DropdownMenuItem(
                  value: ShakePickDuration.quick,
                  child: Text('Rapide · ≤ 30 min'),
                ),
                DropdownMenuItem(
                  value: ShakePickDuration.medium,
                  child: Text('Moyen · 30–60 min'),
                ),
                DropdownMenuItem(
                  value: ShakePickDuration.long,
                  child: Text('Long · 60+ min'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _filters = ShakePickFilters(
                    playerCount: _filters.playerCount,
                    duration: v,
                  );
                  _picked = null;
                });
              },
            ),
            if (_filters.hasActive)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _filters = const ShakePickFilters();
                    _picked = null;
                  }),
                  icon: const Icon(Icons.filter_alt_off, size: 18),
                  label: const Text('Réinitialiser'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickArea() {
    if (_picked != null) {
      return _buildResultCard(_picked!);
    }

    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.vibration,
            size: 72,
            color: Colors.deepPurple.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            _picking ? '…' : '?',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple.shade200,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(CollectionItem item) {
    final players = formatPlayerCount(item.minPlayers, item.maxPlayers);
    final time = formatPlayingTime(item.playingTime);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 140,
                height: 140,
                child: item.imageUrl != null
                    ? BggNetworkImage(url: item.imageUrl!)
                    : ColoredBox(
                        color: item.category.color.withValues(alpha: 0.2),
                        child: Icon(item.category.icon, size: 48),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              item.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (players != null || time != null) ...[
              const SizedBox(height: 6),
              Text(
                [if (players != null) players, if (time != null) time]
                    .join(' · '),
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
            if (item.isGroupOwned && item.groupName != null) ...[
              const SizedBox(height: 4),
              Text(
                item.groupName!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.deepPurple.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
