import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_category.dart';
import '../models/collection_item.dart';
import '../utils/collection_item_filters.dart';
import '../utils/collection_item_scope.dart';
import '../widgets/app_app_bar.dart';
import '../widgets/bgg_network_image.dart';
import 'item_detail_screen.dart';

/// Secoue le téléphone (mobile) ou appuie sur le bouton pour tirer un objet au hasard.
class ShakePickScreen extends StatefulWidget {
  final CollectionCategory? category;

  const ShakePickScreen({super.key, this.category});

  @override
  State<ShakePickScreen> createState() => _ShakePickScreenState();
}

class _ShakePickScreenState extends State<ShakePickScreen>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  List<CollectionItem> _candidates = [];
  CollectionItem? _picked;
  bool _loading = true;
  bool _picking = false;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  int _lastShakeMs = 0;

  late AnimationController _pulseController;

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
        _candidates = [];
        return;
      }

      var query = CollectionItemScope.personal(
        Supabase.instance.client
            .from('collection_items')
            .select()
            .eq('is_wishlist', false)
            .eq('is_sold', false)
            .eq('is_for_sale', false),
        userId: userId,
      );

      if (widget.category != null) {
        query = query.eq('category', widget.category!.dbValue);
      }

      final rows = await query;
      _candidates = (rows as List)
          .map((r) => CollectionItem.fromJson(Map<String, dynamic>.from(r)))
          .where(isShakePickCandidate)
          .toList();
    } catch (_) {
      _candidates = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _startShakeListener() {
    // Accélération sans gravité : bien plus fiable que le capteur brut.
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
    if (_picking || _candidates.isEmpty) return;

    setState(() {
      _picking = true;
      _picked = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final item = _candidates[_random.nextInt(_candidates.length)];
    if (mounted) {
      setState(() {
        _picked = item;
        _picking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.category == CollectionCategory.boardgame
        ? 'À quoi on joue ce soir ?'
        : 'Tirage au sort';

    return Scaffold(
      appBar: AppAppBar(title: title),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _candidates.isEmpty
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
              'Aucun objet éligible',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.category == null
                  ? 'Ajoute des objets à ta collection (hors wishlist et hors vente).'
                  : 'Cette catégorie n\'a pas d\'objet disponible pour un tirage.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            '${_candidates.length} objet${_candidates.length > 1 ? 's' : ''} dans le tirage',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          Expanded(child: Center(child: _buildPickArea())),
          const SizedBox(height: 24),
          if (!kIsWeb)
            Text(
              'Secoue le téléphone pour choisir un jeu',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.deepPurple.shade700,
              ),
            )
          else
            const Text(
              'Sur le web, utilise le bouton ci-dessous',
              style: TextStyle(color: Colors.grey),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _picking ? null : _pickRandom,
            icon: _picking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.shuffle),
            label: Text(_picking ? 'Tirage…' : 'Tirer au sort'),
          ),
          if (_picked != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ItemDetailScreen(item: _picked!),
                ),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Voir la fiche'),
            ),
          ],
        ],
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
            const SizedBox(height: 4),
            Text(
              item.category.label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
